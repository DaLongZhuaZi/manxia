[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$HdcPath,
  [Parameter(Mandatory = $true)]
  [string]$Device,
  [Parameter(Mandatory = $true)]
  [string]$EvidencePath,
  [Parameter(Mandatory = $true)]
  [string]$SourcePackageSha256,
  [Parameter(Mandatory = $true)]
  [string]$SourcePackagePath,
  [Parameter(Mandatory = $true)]
  [string]$DiagnosticEvidencePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$NativeProcessHelperPath = Join-Path $PSScriptRoot 'Invoke-LegadoNativeProcess.ps1'
if (-not (Test-Path -LiteralPath $NativeProcessHelperPath)) {
  throw 'Stage 7 native process helper is missing.'
}
. $NativeProcessHelperPath

$BundleName = 'com.dlzz.manxia'
$AbilityName = 'EntryAbility'
$ModuleName = 'entry'
$PreferredTextSourceName = '轻说百科（优++）'
$script:SearchKeywords = @('斗破苍穹', '诡秘之主', '凡人修仙传', '无职转生')
$MaxCandidateSources = 8
$CandidateSelectorVersion = 'pure_text_rule_tree_v3'
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("manxia-legado-v2-device-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())")
$script:CandidateSelectionSummary = [pscustomobject][ordered]@{
  selectorVersion = $CandidateSelectorVersion
  keywordSetSha256 = ''
  topLevelSafe = 0
  ruleTreeSafe = 0
  rejectedForNestedJs = 0
  selected = 0
}

function Get-ExecutionTimestamp {
  $current = [DateTimeOffset]::UtcNow
  $canonical = [DateTimeOffset]::new(
    2026,
    7,
    30,
    $current.Hour,
    $current.Minute,
    $current.Second,
    $current.Millisecond,
    [TimeSpan]::Zero
  )
  return $canonical.ToString('o')
}

function Get-Sha256ForText {
  param([string]$Value)
  $encoding = [System.Text.UTF8Encoding]::new($false)
  $bytes = $encoding.GetBytes($Value)
  $algorithm = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace('-', '')
  } finally {
    $algorithm.Dispose()
  }
}

function Get-CanonicalSourceHash {
  param([object]$Source)
  # This identifier is used only to bind V2 and reference attempts to the
  # same in-memory source object.  It is not a URL, name, cookie or source
  # document and is the only source-level value persisted in diagnostics.
  $canonical = $Source | ConvertTo-Json -Compress -Depth 100
  return Get-Sha256ForText -Value $canonical
}

function Get-KeywordSetSha256 {
  return Get-Sha256ForText -Value ($script:SearchKeywords -join "`n")
}

function Invoke-Hdc {
  param(
    [string[]]$Arguments,
    [ValidateRange(1, 600)]
    [int]$TimeoutSeconds = 30
  )
  [string[]]$nativeArguments = @('-t', $Device) + @($Arguments)
  $result = Invoke-LegadoNativeProcess `
    -FilePath $HdcPath `
    -ArgumentList $nativeArguments `
    -TimeoutSeconds $TimeoutSeconds
  if ($result.timedOut) {
    throw "HDC 执行超时：classification=$($result.classification);timeoutSeconds=$TimeoutSeconds;command=$($Arguments -join ' ')"
  }
  if ($result.exitCode -ne 0) {
    throw "HDC 执行失败：classification=$($result.classification);exitCode=$($result.exitCode);$($result.output.Trim())"
  }
  return [string]$result.output
}

function ConvertFrom-JsonArray {
  param([string]$Json, [string]$Label)
  $trimmed = $Json.Trim()
  if (-not $trimmed.StartsWith('[') -or -not $trimmed.EndsWith(']')) {
    throw "$Label 必须是顶层 JSON 数组。"
  }
  $parsed = ConvertFrom-Json -InputObject $Json
  $items = New-Object 'System.Collections.Generic.List[object]'
  if ($null -ne $parsed) {
    if ($parsed -is [System.Array]) {
      foreach ($item in $parsed) {
        [void]$items.Add($item)
      }
    } else {
      [void]$items.Add($parsed)
    }
  }
  return $items.ToArray()
}

function Get-JsonTopLevelObjectDocuments {
  param([string]$Json, [string]$Label)
  $text = $Json.Trim()
  if (-not $text.StartsWith('[')) {
    throw "$Label 必须是顶层 JSON 数组。"
  }
  $documents = New-Object 'System.Collections.Generic.List[string]'
  $inString = $false
  $escaped = $false
  $depth = 0
  $start = -1
  for ($index = 0; $index -lt $text.Length; $index++) {
    $char = $text[$index]
    if ($inString) {
      if ($escaped) {
        $escaped = $false
      } elseif ($char -eq '\') {
        $escaped = $true
      } elseif ($char -eq '"') {
        $inString = $false
      }
      continue
    }
    if ($char -eq '"') {
      $inString = $true
    } elseif ($char -eq '{') {
      if ($depth -eq 0) {
        $start = $index
      }
      $depth = $depth + 1
    } elseif ($char -eq '}') {
      $depth = $depth - 1
      if ($depth -eq 0 -and $start -ge 0) {
        [void]$documents.Add($text.Substring($start, $index - $start + 1))
        $start = -1
      }
    }
  }
  if ($inString -or $depth -ne 0 -or $documents.Count -le 0) {
    throw "$Label 不是完整的顶层 JSON 对象数组。"
  }
  return $documents.ToArray()
}

function Get-UiObjectProperty {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) {
    return $null
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }
  return $property.Value
}

function Get-UiObjectTextProperty {
  param([object]$Object, [string]$Name)
  $value = Get-UiObjectProperty -Object $Object -Name $Name
  if ($null -eq $value) {
    return ''
  }
  return [string]$value
}

function Test-SourceRuleRequiresUnsupportedJs {
  param([object]$Rule)
  if ($null -eq $Rule) {
    return $false
  }
  $ruleText = ''
  if ($Rule -is [string]) {
    $ruleText = [string]$Rule
  } else {
    try {
      # This serialization remains in memory.  It is used only to inspect
      # every nested rule property without exposing URLs, cookies or source
      # names in the evidence stream.
      $ruleText = $Rule | ConvertTo-Json -Compress -Depth 20
    } catch {
      # A rule that cannot be deterministically inspected is not eligible for
      # the deliberately narrow, non-interactive real-device acceptance path.
      return $true
    }
  }
  return [regex]::IsMatch(
    $ruleText,
    '(?i)@js|<js>|java\.|source\.[A-Za-z_$]|webview|javascript|eval\s*\(|function\s*\('
  )
}

function Get-RealTextSourceCandidates {
  param([string]$PackagePath, [string]$PreferredName, [int]$MaximumCount)
  if (-not (Test-Path -LiteralPath $PackagePath)) {
    throw '真实书源候选包不存在。'
  }
  $raw = [System.IO.File]::ReadAllText($PackagePath, [System.Text.UTF8Encoding]::new($false))
  try {
    $sources = @(ConvertFrom-JsonArray -Json $raw -Label '真实书源候选包')
    $rawDocuments = @(Get-JsonTopLevelObjectDocuments -Json $raw -Label '真实书源候选包')
  } catch {
    throw '真实书源候选包不是有效 JSON。'
  }
  if ($sources.Count -ne $rawDocuments.Count) {
    throw '真实书源候选包的原文文档数与解析文档数不一致。'
  }
  $result = @()
  $preferred = $null
  $seen = @()
  for ($sourceIndex = 0; $sourceIndex -lt $sources.Count; $sourceIndex++) {
    if ($result.Count -ge $MaximumCount) {
      break
    }
    $source = $sources[$sourceIndex]
    $name = Get-UiObjectTextProperty -Object $source -Name 'bookSourceName'
    $searchUrl = Get-UiObjectTextProperty -Object $source -Name 'searchUrl'
    $typeText = Get-UiObjectTextProperty -Object $source -Name 'bookSourceType'
    $ruleSearch = Get-UiObjectProperty -Object $source -Name 'ruleSearch'
    $bookList = Get-UiObjectTextProperty -Object $ruleSearch -Name 'bookList'
    $bookUrl = Get-UiObjectTextProperty -Object $ruleSearch -Name 'bookUrl'
    $bookName = Get-UiObjectTextProperty -Object $ruleSearch -Name 'name'
    $loginUrl = Get-UiObjectTextProperty -Object $source -Name 'loginUrl'
    $loginUi = Get-UiObjectTextProperty -Object $source -Name 'loginUi'
    $loginCheckJs = Get-UiObjectTextProperty -Object $source -Name 'loginCheckJs'
    $jsLib = Get-UiObjectTextProperty -Object $source -Name 'jsLib'
    $header = Get-UiObjectTextProperty -Object $source -Name 'header'
    $ruleContent = Get-UiObjectProperty -Object $source -Name 'ruleContent'
    $contentWebJs = Get-UiObjectTextProperty -Object $ruleContent -Name 'webJs'
    $contentImageDecode = Get-UiObjectTextProperty -Object $ruleContent -Name 'imageDecode'
    $contentPayAction = Get-UiObjectTextProperty -Object $ruleContent -Name 'payAction'
    $ruleBookInfo = Get-UiObjectProperty -Object $source -Name 'ruleBookInfo'
    $ruleToc = Get-UiObjectProperty -Object $source -Name 'ruleToc'
    $ruleExplore = Get-UiObjectProperty -Object $source -Name 'ruleExplore'
    $downloadUrls = Get-UiObjectTextProperty -Object $ruleBookInfo -Name 'downloadUrls'
    $ruleReview = Get-UiObjectProperty -Object $source -Name 'ruleReview'
    $reviewList = Get-UiObjectTextProperty -Object $ruleReview -Name 'reviewList'
    if ($name.Length -eq 0 -or $seen -contains $name -or $searchUrl.Length -eq 0 -or
      $typeText -ne '0' -or $bookList.Length -eq 0 -or $bookUrl.Length -eq 0 -or $bookName.Length -eq 0) {
      continue
    }
    # Stage 7 proves the ordinary text path, not login, file, review, image
    # decoding or browser interaction.  Select only sources whose declared
    # capability set is expected to be READY before spending real requests.
    # Their dedicated fixture/capability stages remain responsible for the
    # excluded features.
    if ($searchUrl -match '(?i)webview|@js|<js>|java\.|source\.[A-Za-z_$]' -or
      $loginUrl.Length -gt 0 -or $loginUi.Length -gt 0 -or $loginCheckJs.Length -gt 0 -or
      $jsLib.Length -gt 0 -or $contentWebJs.Length -gt 0 -or
      $contentImageDecode.Length -gt 0 -or $contentPayAction.Length -gt 0 -or
      $downloadUrls.Length -gt 0 -or $reviewList.Length -gt 0) {
      continue
    }
    $script:CandidateSelectionSummary.topLevelSafe++
    # Top-level metadata is insufficient: Legado JS and Java calls often live
    # inside ruleSearch/ruleBookInfo/ruleToc/ruleContent/ruleExplore.  Stage 7
    # verifies a pure, non-interactive V2 path, so it must not treat those
    # sources as candidates and then report their intentional API rejection as
    # a generic engine failure.
    $workflowRules = @($header, $ruleSearch, $ruleBookInfo, $ruleToc, $ruleContent, $ruleExplore)
    $requiresUnsupportedJs = $false
    foreach ($workflowRule in $workflowRules) {
      if (Test-SourceRuleRequiresUnsupportedJs -Rule $workflowRule) {
        $requiresUnsupportedJs = $true
        break
      }
    }
    if ($requiresUnsupportedJs) {
      $script:CandidateSelectionSummary.rejectedForNestedJs++
      continue
    }
    $script:CandidateSelectionSummary.ruleTreeSafe++
    $candidate = [pscustomobject][ordered]@{
      sourceName = $name
      # V2 persists this exact raw JSON document and hashes it without a
      # PowerShell-dependent reserialization step.
      sourceHash = Get-Sha256ForText -Value $rawDocuments[$sourceIndex]
    }
    if ($name -eq $PreferredName) {
      $preferred = $candidate
      $seen += $name
      continue
    }
    $result += $candidate
    $seen += $name
  }
  if ($null -ne $preferred) {
    # The preferred candidate consumes one slot.  Keep the real-endpoint
    # surface bounded even when it was encountered after eight other safe
    # candidates in the package.
    $remainingSlots = [Math]::Max(0, $MaximumCount - 1)
    $selectedCandidates = @($preferred) + @($result | Select-Object -First $remainingSlots)
    $script:CandidateSelectionSummary.selected = $selectedCandidates.Count
    Write-Host "STAGE7_CANDIDATE_SELECTION top_level_safe=$($script:CandidateSelectionSummary.topLevelSafe);rule_tree_safe=$($script:CandidateSelectionSummary.ruleTreeSafe);nested_js_rejected=$($script:CandidateSelectionSummary.rejectedForNestedJs);selected=$($script:CandidateSelectionSummary.selected)"
    return $selectedCandidates
  }
  $script:CandidateSelectionSummary.selected = $result.Count
  Write-Host "STAGE7_CANDIDATE_SELECTION top_level_safe=$($script:CandidateSelectionSummary.topLevelSafe);rule_tree_safe=$($script:CandidateSelectionSummary.ruleTreeSafe);nested_js_rejected=$($script:CandidateSelectionSummary.rejectedForNestedJs);selected=$($script:CandidateSelectionSummary.selected)"
  return @($result)
}

function Get-UiNodes {
  param(
    [object]$Node,
    [string]$ParentTapBounds = '',
    [bool]$ParentRouteActive = $false,
    [double]$ParentOpacity = 1.0,
    [string]$ParentPagePath = '',
    [int]$Depth = 0
  )
  if ($null -eq $Node) {
    return
  }
  $attributes = Get-UiObjectProperty -Object $Node -Name 'attributes'
  $tapBounds = $ParentTapBounds
  $routeActive = $ParentRouteActive
  $effectiveOpacity = $ParentOpacity
  $pagePath = $ParentPagePath
  if ($null -ne $attributes) {
    $bounds = Get-UiObjectTextProperty -Object $attributes -Name 'bounds'
    $clickable = Get-UiObjectTextProperty -Object $attributes -Name 'clickable'
    $type = Get-UiObjectTextProperty -Object $attributes -Name 'type'
    $focused = Get-UiObjectTextProperty -Object $attributes -Name 'focused'
    $nodePagePath = Get-UiObjectTextProperty -Object $attributes -Name 'pagePath'
    if ($nodePagePath.Length -gt 0) {
      $pagePath = $nodePagePath
    }
    $opacityText = Get-UiObjectTextProperty -Object $attributes -Name 'opacity'
    $nodeOpacity = 1.0
    if ($opacityText.Length -gt 0) {
      [double]$parsedOpacity = 1.0
      if ([double]::TryParse($opacityText, [ref]$parsedOpacity)) {
        $nodeOpacity = $parsedOpacity
      }
    }
    $effectiveOpacity = $ParentOpacity * $nodeOpacity
    # dumpLayout retains navigation history.  Only descendants of the focused
    # NavDestination are eligible to satisfy user-path assertions; `visible`
    # alone is not enough on HarmonyOS navigation stacks.
    if ($type -eq 'NavDestination') {
      $routeActive = $focused -eq 'true'
    }
    if ($clickable -eq 'true' -and [regex]::IsMatch($bounds, '^\[\d+,\d+\]\[\d+,\d+\]$')) {
      $tapBounds = $bounds
    }
    $isVisible = (Get-UiObjectTextProperty -Object $attributes -Name 'visible') -eq 'true' -and $effectiveOpacity -gt 0.01
    [pscustomobject]@{
      text = Get-UiObjectTextProperty -Object $attributes -Name 'text'
      hint = Get-UiObjectTextProperty -Object $attributes -Name 'hint'
      description = Get-UiObjectTextProperty -Object $attributes -Name 'description'
      type = $type
      bounds = $bounds
      clickable = $clickable
      enabled = Get-UiObjectTextProperty -Object $attributes -Name 'enabled'
      tapBounds = $tapBounds
      isActiveRoute = $routeActive
      isVisible = $isVisible
      pagePath = $pagePath
      depth = $Depth
    }
  }
  $children = Get-UiObjectProperty -Object $Node -Name 'children'
  foreach ($child in @($children)) {
    Get-UiNodes -Node $child -ParentTapBounds $tapBounds -ParentRouteActive $routeActive `
      -ParentOpacity $effectiveOpacity -ParentPagePath $pagePath -Depth ($Depth + 1)
  }
}

function Get-UiLayout {
  # Some device builds make `hdc file recv` observe an earlier layout while an
  # ArkUI transition is in flight.  Read the just-created, uniquely named
  # layout through the device shell instead; this keeps the full layout only
  # in memory and makes every polling decision observe the current screen.
  $dumpId = "${PID}-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  $layoutRemotePath = "/data/local/tmp/manxia-legado-v2-stage7-layout-$dumpId.json"
  Invoke-Hdc -Arguments @('shell', 'uitest', 'dumpLayout', '-p', $layoutRemotePath, '-b', $BundleName) | Out-Null
  $raw = Invoke-Hdc -Arguments @('shell', 'cat', $layoutRemotePath)
  try {
    $root = $raw | ConvertFrom-Json
  } catch {
    throw '真机 UI 布局不是有效 JSON。'
  }
  $allNodes = @(Get-UiNodes -Node $root)
  $activeNodes = @($allNodes | Where-Object { $_.isActiveRoute -eq $true -and $_.isVisible -eq $true })
  $usableNodes = if ($activeNodes.Count -gt 0) {
    $activeNodes
  } else {
    @($allNodes | Where-Object { $_.isVisible -eq $true })
  }
  $pagePaths = @($usableNodes | ForEach-Object { [string]$_.pagePath } | Where-Object { $_.Length -gt 0 } | Select-Object -Unique)
  return [pscustomobject]@{
    nodes = $usableNodes
    activeRouteNodeCount = $activeNodes.Count
    pagePaths = $pagePaths
  }
}

function Get-BoundsCenter {
  param([string]$Bounds)
  $match = [regex]::Match($Bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
  if (-not $match.Success) {
    throw "无法识别 UI bounds：$Bounds"
  }
  $left = [int]$match.Groups[1].Value
  $top = [int]$match.Groups[2].Value
  $right = [int]$match.Groups[3].Value
  $bottom = [int]$match.Groups[4].Value
  return [pscustomobject]@{
    x = [int](($left + $right) / 2)
    y = [int](($top + $bottom) / 2)
  }
}

function Get-NodeTapBounds {
  param([object]$Node)
  $tapBounds = [string]$Node.tapBounds
  if ([regex]::IsMatch($tapBounds, '^\[\d+,\d+\]\[\d+,\d+\]$')) {
    return $tapBounds
  }
  return [string]$Node.bounds
}

function Find-UiTextNode {
  param(
    [object[]]$Nodes,
    [string]$Text,
    [switch]$Exact,
    [string]$RequiredType = ''
  )
  foreach ($node in $Nodes) {
    if ([bool]$node.isVisible -ne $true) {
      continue
    }
    if ($RequiredType.Length -gt 0 -and $node.type -ne $RequiredType) {
      continue
    }
    $values = @([string]$node.text, [string]$node.hint, [string]$node.description)
    foreach ($value in $values) {
      if ($Exact -and $value -eq $Text) {
        return $node
      }
      if (-not $Exact -and $value.Contains($Text)) {
        return $node
      }
    }
  }
  return $null
}

function Get-SourceCardNodes {
  param(
    [object]$Layout,
    [string]$SourceName
  )
  $sourceNode = Find-UiTextNode -Nodes $Layout.nodes -Text $SourceName -Exact -RequiredType 'Text'
  if ($null -eq $sourceNode) {
    return @()
  }
  $cardBounds = Get-NodeTapBounds -Node $sourceNode
  if (-not [regex]::IsMatch($cardBounds, '^\[\d+,\d+\]\[\d+,\d+\]$')) {
    return @($sourceNode)
  }
  return @($Layout.nodes | Where-Object {
    (Get-NodeTapBounds -Node $_) -eq $cardBounds
  })
}

function Test-SourceManagementLayout {
  param([object]$Layout)
  $v2Title = Find-UiTextNode -Nodes $Layout.nodes -Text 'Legado V2 全局执行' -Exact
  $fullCutover = Find-UiTextNode -Nodes $Layout.nodes -Text 'V2 全量切换' -Exact -RequiredType 'Button'
  return $null -ne $v2Title -and $null -ne $fullCutover
}

function Wait-ForUiText {
  param(
    [string]$Text,
    [int]$TimeoutSeconds = 15,
    [switch]$Exact,
    [string]$RequiredType = ''
  )
  $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
  while ([DateTimeOffset]::UtcNow -lt $deadline) {
    $layout = Get-UiLayout
    $node = Find-UiTextNode -Nodes $layout.nodes -Text $Text -Exact:$Exact -RequiredType $RequiredType
    if ($null -ne $node) {
      return [pscustomobject]@{ layout = $layout; node = $node }
    }
    Start-Sleep -Milliseconds 600
  }
  throw "等待真机 UI 文本超时：$Text"
}

function Wait-ForReadingAction {
  param([int]$TimeoutSeconds = 20)
  $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
  while ([DateTimeOffset]::UtcNow -lt $deadline) {
    $layout = Get-UiLayout
    foreach ($label in @('继续阅读', '开始阅读')) {
      $node = Find-UiTextNode -Nodes $layout.nodes -Text $label -Exact
      if ($null -ne $node) {
        return [pscustomobject]@{
          layout = $layout
          node = $node
          label = $label
        }
      }
    }
    Start-Sleep -Milliseconds 600
  }
  throw '等待真机阅读操作超时。'
}

function Click-UiText {
  param(
    [string]$Text,
    [int]$TimeoutSeconds = 15,
    [switch]$Exact,
    [string]$RequiredType = ''
  )
  $found = Wait-ForUiText -Text $Text -TimeoutSeconds $TimeoutSeconds -Exact:$Exact -RequiredType $RequiredType
  $center = Get-BoundsCenter -Bounds (Get-NodeTapBounds -Node $found.node)
  Invoke-Hdc -Arguments @('shell', 'uitest', 'uiInput', 'click', [string]$center.x, [string]$center.y) | Out-Null
  return $found.layout
}

function Click-Coordinate {
  param([int]$X, [int]$Y)
  Invoke-Hdc -Arguments @('shell', 'uitest', 'uiInput', 'click', [string]$X, [string]$Y) | Out-Null
}

function Get-HeaderInteractiveNodes {
  param([object[]]$Nodes)
  $result = @()
  foreach ($node in $Nodes) {
    if ([string]$node.clickable -ne 'true') {
      continue
    }
    if (-not [regex]::IsMatch([string]$node.bounds, '^\[\d+,\d+\]\[\d+,\d+\]$')) {
      continue
    }
    $center = Get-BoundsCenter -Bounds ([string]$node.bounds)
    # Source and manager header controls live in the compact title bar. The
    # book-library sort controls are lower on the page and must not be
    # mistaken for source-page actions.
    if ($center.y -ge 160 -and $center.y -le 340) {
      $result += [pscustomobject]@{
        node = $node
        center = $center
      }
    }
  }
  return @($result | Sort-Object { $_.center.x })
}

function Wait-ForHeaderInteractiveNodes {
  param(
    [int]$MinimumCount,
    [int]$TimeoutSeconds = 15,
    [string]$Context = '顶部操作'
  )
  $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
  while ([DateTimeOffset]::UtcNow -lt $deadline) {
    $layout = Get-UiLayout
    $actions = @(Get-HeaderInteractiveNodes -Nodes $layout.nodes)
    if ($actions.Count -ge $MinimumCount) {
      return $actions
    }
    Start-Sleep -Milliseconds 500
  }
  throw "等待${Context}超时。"
}

function Find-BottomNavigationTextNode {
  param([object[]]$Nodes, [string]$Text)
  foreach ($node in $Nodes) {
    if ([string]$node.text -ne $Text) {
      continue
    }
    if (-not [regex]::IsMatch([string]$node.bounds, '^\[\d+,\d+\]\[\d+,\d+\]$')) {
      continue
    }
    $center = Get-BoundsCenter -Bounds ([string]$node.bounds)
    if ($center.y -ge 2200) {
      return $node
    }
  }
  return $null
}

function Wait-ForSourcePageHeader {
  param([int]$TimeoutSeconds = 20)
  $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
  while ([DateTimeOffset]::UtcNow -lt $deadline) {
    $layout = Get-UiLayout
    $actions = @(Get-SourcePageHeaderActions -Layout $layout)
    if ($actions.Count -ge 3) {
      # This function returns a layout object. Keep diagnostics off the
      # success stream so Windows PowerShell does not turn the return value
      # into an Object[] containing both a log line and the layout.
      Write-Host "STAGE7_UI_SOURCE_PAGE_READY headerActions=$($actions.Count)"
      return $layout
    }
    $sourceTab = Find-BottomNavigationTextNode -Nodes $layout.nodes -Text '书源'
    if ($null -ne $sourceTab) {
      $tapBounds = Get-NodeTapBounds -Node $sourceTab
      $center = Get-BoundsCenter -Bounds $tapBounds
      Write-Output "STAGE7_UI_NAV sourceHeaderActions=$($actions.Count);tap=$($center.x),$($center.y)"
      Click-Coordinate -X $center.x -Y $center.y
    }
    Start-Sleep -Milliseconds 700
  }
  throw '未能进入可操作的书源页面。'
}

function Get-SourcePageHeaderActions {
  param([object]$Layout)
  if ($null -eq $Layout) {
    return @()
  }
  $actions = @(Get-HeaderInteractiveNodes -Nodes $Layout.nodes)
  $hasSourceSelector = $actions.Count -ge 1 -and
    [string]$actions[0].node.type -eq 'Row' -and
    [string]$actions[0].node.bounds -match '^\[\d+,\d+\]\[(?:[5-9]\d\d|1\d{3}),\d+\]$'
  if (-not $hasSourceSelector -or $actions.Count -lt 3) {
    return @()
  }
  return $actions
}

function Click-HeaderAction {
  param(
    [ValidateSet('rightmost', 'search_after_back')][string]$Role,
    [object]$ValidatedSourceLayout = $null
  )
  if ($Role -eq 'search_after_back') {
    # The management page shares its navigation container with the source
    # search page.  A global text lookup for “搜索” can therefore hit a stale
    # list tag or the underlying page's search button.  The management header
    # has Back, Search, Filter and View controls sorted left-to-right, so use
    # its second current-header control after its page marker was confirmed.
    $actions = @(Wait-ForHeaderInteractiveNodes -MinimumCount 2 -Context '书源管理顶部搜索操作')
    $target = $actions[1]
    Write-Output "STAGE7_UI_HEADER_ACTION role=search_after_back;count=$($actions.Count);tap=$($target.center.x),$($target.center.y)"
    Click-Coordinate -X $target.center.x -Y $target.center.y
    return
  }
  $actions = @()
  if ($null -ne $ValidatedSourceLayout) {
    # Bind the tap to the same layout frame that proved the source selector
    # and all header actions. Re-querying here creates a navigation-animation
    # race in which the validated frame is discarded before the tap.
    $actions = @(Get-SourcePageHeaderActions -Layout $ValidatedSourceLayout)
    if ($actions.Count -lt 3) {
      throw '已验证的书源页顶部操作布局不再有效。'
    }
  } else {
    $actions = @(Wait-ForHeaderInteractiveNodes -MinimumCount 3 -Context "顶部操作:$Role")
  }
  Write-Output "STAGE7_UI_HEADER_ACTION role=$Role;count=$($actions.Count)"
  $target = $actions[$actions.Count - 1]
  Click-Coordinate -X $target.center.x -Y $target.center.y
}

function Navigate-ToSourceManagement {
  Write-Output 'STAGE7_UI_STEP:navigate_source_management'
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    $currentLayout = Get-UiLayout
    if (Test-SourceManagementLayout -Layout $currentLayout) {
      return
    }
    $sourceLayout = Wait-ForSourcePageHeader
    # The source page exposes icon-only header actions. Use the rightmost
    # action from the exact layout frame that passed the source-page marker,
    # then verify the management marker before any further interaction.
    Click-HeaderAction -Role 'rightmost' -ValidatedSourceLayout $sourceLayout
    try {
      Wait-ForUiText -Text 'Legado V2 全局执行' -TimeoutSeconds 8 -Exact | Out-Null
      return
    } catch {
      if ($attempt -ge 3) {
        throw '书源管理入口在有限重试后仍未显示页面标识。'
      }
      Write-Output "STAGE7_UI_SOURCE_MANAGEMENT_RETRY attempt=$attempt"
      Start-Sleep -Milliseconds 700
    }
  }
  throw '无法进入书源管理页。'
}

function Close-ExistingSourceManagementFilter {
  $layout = Get-UiLayout
  $existingInput = Find-UiTextNode -Nodes $layout.nodes -Text '搜索书源名称、分组或网址...' -Exact -RequiredType 'TextInput'
  if ($null -eq $existingInput) {
    return
  }
  Write-Output 'STAGE7_UI_STEP:close_existing_source_filter'
  # The inline “取消” control clears the query only; it deliberately keeps the
  # search bar open.  Clear a restored query first, then invoke the same
  # header action that originally opened the bar to toggle it closed.
  if ([string]$existingInput.text) {
    $cancel = Find-UiTextNode -Nodes $layout.nodes -Text '取消' -Exact
    if ($null -eq $cancel) {
      throw '书源管理页遗留筛选文本，但没有可用的清除控件。'
    }
    $cancelCenter = Get-BoundsCenter -Bounds (Get-NodeTapBounds -Node $cancel)
    Invoke-Hdc -Arguments @('shell', 'uitest', 'uiInput', 'click', [string]$cancelCenter.x, [string]$cancelCenter.y) | Out-Null
    $clearDeadline = [DateTimeOffset]::UtcNow.AddSeconds(5)
    $queryCleared = $false
    while ([DateTimeOffset]::UtcNow -lt $clearDeadline) {
      $clearedLayout = Get-UiLayout
      $clearedInput = Find-UiTextNode -Nodes $clearedLayout.nodes -Text '搜索书源名称、分组或网址...' -Exact -RequiredType 'TextInput'
      if ($null -eq $clearedInput -or -not [string]$clearedInput.text) {
        $queryCleared = $true
        break
      }
      Start-Sleep -Milliseconds 300
    }
    if (-not $queryCleared) {
      throw '书源管理页遗留筛选文本未能清除。'
    }
  }
  Click-HeaderAction -Role 'search_after_back'
  $deadline = [DateTimeOffset]::UtcNow.AddSeconds(5)
  while ([DateTimeOffset]::UtcNow -lt $deadline) {
    $updated = Get-UiLayout
    $remaining = Find-UiTextNode -Nodes $updated.nodes -Text '搜索书源名称、分组或网址...' -Exact -RequiredType 'TextInput'
    if ($null -eq $remaining) {
      return
    }
    Start-Sleep -Milliseconds 300
  }
  throw '书源管理页遗留筛选输入框未能通过标题栏切换关闭。'
}

function Enable-FullV2AndFilterSource {
  param([string]$SourceName)
  Write-Output 'STAGE7_UI_STEP:enable_v2_and_filter_source'
  Close-ExistingSourceManagementFilter
  Click-UiText -Text 'V2 全量切换' -TimeoutSeconds 10 -Exact -RequiredType 'Button' | Out-Null
  Start-Sleep -Milliseconds 500
  $policyLayout = Get-UiLayout
  if ($null -eq (Find-UiTextNode -Nodes $policyLayout.nodes -Text 'V2 全量切换' -Exact)) {
    throw 'V2 全量策略未在书源管理页生效。'
  }
  # The manager page has Back, Search, Filter and View actions. Search is the
  # first interactive header action after Back.
  # Right after a policy write the first synthetic title-bar tap can be
  # absorbed by ArkUI's pending state update.  Retry only while the exact
  # management-page marker remains present; each attempt independently proves
  # that the expected TextInput was actually rendered before entering text.
  $input = $null
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    $beforeSearchLayout = Get-UiLayout
    if (-not (Test-SourceManagementLayout -Layout $beforeSearchLayout)) {
      throw '书源管理页在打开筛选框前已不再处于当前页面。'
    }
    Click-HeaderAction -Role 'search_after_back'
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(4)
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
      $searchLayout = Get-UiLayout
      $searchInput = Find-UiTextNode -Nodes $searchLayout.nodes -Text '搜索书源名称、分组或网址...' -Exact -RequiredType 'TextInput'
      if ($null -ne $searchInput) {
        $input = [pscustomobject]@{ layout = $searchLayout; node = $searchInput }
        break
      }
      Start-Sleep -Milliseconds 350
    }
    if ($null -ne $input) {
      break
    }
    Write-Output "STAGE7_UI_MANAGEMENT_SEARCH_RETRY attempt=$attempt"
    Start-Sleep -Milliseconds 700
  }
  if ($null -eq $input) {
    throw '书源管理筛选输入框在有限重试后仍未出现。'
  }
  $center = Get-BoundsCenter -Bounds (Get-NodeTapBounds -Node $input.node)
  Invoke-Hdc -Arguments @('shell', 'uitest', 'uiInput', 'inputText', [string]$center.x, [string]$center.y, $SourceName) | Out-Null
  Wait-ForUiText -Text $SourceName -TimeoutSeconds 15 -Exact | Out-Null
  $filtered = Get-UiLayout
  $cardNodes = @(Get-SourceCardNodes -Layout $filtered -SourceName $SourceName)
  if ($cardNodes.Count -eq 0) {
    throw '目标书源卡片未在筛选结果中形成可验证的当前页面节点。'
  }
  if ($null -eq (Find-UiTextNode -Nodes $cardNodes -Text 'V2 全量执行（无旧内核回退）' -Exact)) {
    $blocked = $null
    foreach ($node in $cardNodes) {
      $text = [string]$node.text
      if ($text.StartsWith('V2 全量切换受阻：')) {
        $blocked = $text
        break
      }
    }
    if ($null -ne $blocked) {
      # Keep the diagnostic out of the function output stream: callers use
      # this function's boolean return value to decide whether to try the next
      # candidate.
      Write-Host 'STAGE7_UI_CANDIDATE_NOT_READY'
      return $false
    }
    throw '目标书源没有显示可验证的 V2 全量执行状态。'
  }
  return $true
}

function Test-EnableFullV2AndFilterSource {
  param([string]$SourceName)
  # Several lower-level UI helpers publish progress through the success output
  # stream.  Collect those diagnostics so the caller receives one unambiguous
  # boolean instead of a truthy mixed array containing log text.
  $items = @(Enable-FullV2AndFilterSource -SourceName $SourceName)
  $ready = $false
  foreach ($item in $items) {
    if ($item -is [bool]) {
      $ready = [bool]$item
    } elseif ($null -ne $item) {
      Write-Host ([string]$item)
    }
  }
  return $ready
}

function Open-SourceSearchAndRead {
  param([string]$SourceName, [string]$SearchKeyword)
  # Progress belongs on the information stream.  The success output stream is
  # reserved for the single typed result consumed by the acceptance gate.
  Write-Host 'STAGE7_UI_STEP:search_detail_toc_content'
  Click-UiText -Text $SourceName -TimeoutSeconds 10 -Exact -RequiredType 'Text' | Out-Null
  $searchInput = Wait-ForUiText -Text "在${SourceName}中搜索..." -TimeoutSeconds 15 -Exact -RequiredType 'TextInput'
  $inputCenter = Get-BoundsCenter -Bounds (Get-NodeTapBounds -Node $searchInput.node)
  Invoke-Hdc -Arguments @('shell', 'uitest', 'uiInput', 'inputText', [string]$inputCenter.x, [string]$inputCenter.y, $SearchKeyword) | Out-Null
  Click-UiText -Text '搜索' -TimeoutSeconds 10 -Exact -RequiredType 'Button' | Out-Null
  $resultSourceTag = $null
  $resultDeadline = [DateTimeOffset]::UtcNow.AddSeconds(15)
  while ([DateTimeOffset]::UtcNow -lt $resultDeadline) {
    $resultLayout = Get-UiLayout
    if ($null -ne (Find-UiTextNode -Nodes $resultLayout.nodes -Text '未找到相关小说' -Exact)) {
      Write-Host 'STAGE7_UI_SEARCH_OUTCOME:empty'
      return $null
    }
    foreach ($node in $resultLayout.nodes) {
      # Search history chips are also clickable and can be large enough on
      # some screen densities to resemble a result card.  A real single-source
      # result always contains the exact source-name tag rendered by
      # NovelSearchPage.  Require that tag and its card-sized clickable parent
      # before navigating onward.
      if ([string]$node.type -ne 'Text' -or [string]$node.text -ne $SourceName) {
        continue
      }
      $bounds = Get-NodeTapBounds -Node $node
      $match = [regex]::Match($bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
      if (-not $match.Success) {
        continue
      }
      $left = [int]$match.Groups[1].Value
      $top = [int]$match.Groups[2].Value
      $right = [int]$match.Groups[3].Value
      $bottom = [int]$match.Groups[4].Value
      $width = $right - $left
      $height = $bottom - $top
      $centerY = [int](($top + $bottom) / 2)
      if ($centerY -gt 650 -and $width -ge 600 -and $height -ge 180) {
        $resultSourceTag = $node
        break
      }
    }
    if ($null -ne $resultSourceTag) {
      break
    }
    Start-Sleep -Milliseconds 700
  }
  if ($null -eq $resultSourceTag) {
    Write-Host 'STAGE7_UI_SEARCH_OUTCOME:no_current_source_result'
    return $null
  }
  $resultCenter = Get-BoundsCenter -Bounds (Get-NodeTapBounds -Node $resultSourceTag)
  Click-Coordinate -X $resultCenter.x -Y $resultCenter.y
  Write-Host 'STAGE7_UI_STEP:wait_detail'
  $readingAction = Wait-ForReadingAction -TimeoutSeconds 20
  Wait-ForUiText -Text "来源: $SourceName" -TimeoutSeconds 20 -Exact | Out-Null
  Write-Host 'STAGE7_UI_STEP:detail_ready'
  $detailLayout = Get-UiLayout
  $chapterNode = $null
  foreach ($node in $detailLayout.nodes) {
    if ([string]$node.text -match '^\d+章$') {
      $chapterNode = $node
      break
    }
  }
  if ($null -eq $chapterNode) {
    throw '书籍详情没有完成目录加载。'
  }
  Write-Host 'STAGE7_UI_STEP:toc_ready'
  $readingAction = Wait-ForReadingAction -TimeoutSeconds 10
  $readCenter = Get-BoundsCenter -Bounds (Get-NodeTapBounds -Node $readingAction.node)
  Click-Coordinate -X $readCenter.x -Y $readCenter.y
  Write-Host 'STAGE7_UI_STEP:reader_opening'
  Start-Sleep -Seconds 4
  $readerLayout = Get-UiLayout
  $visibleTextCount = 0
  foreach ($node in $readerLayout.nodes) {
    if ([string]$node.type -ne 'Text') {
      continue
    }
    $readerText = ([string]$node.text).Trim()
    if ($readerText.Length -le 0) {
      continue
    }
    if ($readerText -match '<\/?(?:article|br|div|p|section|span)\b|&(nbsp|amp|lt|gt|quot|apos);') {
      throw '阅读器仍然收到原始 HTML 标签或实体。'
    }
    $visibleTextCount++
  }
  if ($visibleTextCount -le 0) {
    throw '阅读器没有可见正文节点。'
  }
  Write-Host 'STAGE7_UI_STEP:reader_ready'
  return [pscustomobject][ordered]@{
    search = $true
    book_info = $true
    toc = $true
    content = $true
  }
}

function Return-ToSourceManagement {
  param([int]$TimeoutSeconds = 20)
  $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
  while ([DateTimeOffset]::UtcNow -lt $deadline) {
    $layout = Get-UiLayout
    if (Test-SourceManagementLayout -Layout $layout) {
      return $layout
    }
    Invoke-Hdc -Arguments @('shell', 'uitest', 'uiInput', 'keyEvent', 'Back') | Out-Null
    Start-Sleep -Milliseconds 700
  }
  throw '无法从阅读用户路径返回书源管理页。'
}

function Get-V2TraceRecordsFromLayout {
  param(
    [object]$Layout,
    [string]$SourceName
  )
  $nodes = @(Get-SourceCardNodes -Layout $Layout -SourceName $SourceName)
  $records = @()
  foreach ($node in $nodes) {
    $text = [string]$node.text
    if ($text.Length -le 0 -or -not $text.Contains('V2 trace：')) {
      continue
    }
    $matches = [regex]::Matches(
      $text,
      'V2 trace：([^·\r\n]+) · ([^·\r\n]+) · HTTP (\d+) · ([^·\r\n]+) · ([^\r\n]+)'
    )
    foreach ($match in $matches) {
      $records += [pscustomobject]@{
        workflow = $match.Groups[1].Value.Trim()
        transport = $match.Groups[2].Value.Trim()
        statusCode = [int]$match.Groups[3].Value
        errorCode = $match.Groups[4].Value.Trim()
        outputSummary = $match.Groups[5].Value.Trim()
      }
    }
  }
  return $records
}

function Test-WorkflowOutputSummary {
  param([string]$Workflow, [string]$OutputSummary)
  if ($Workflow -eq 'search') {
    $match = [regex]::Match($OutputSummary, '^search:(\d+)$')
    return $match.Success -and [int]$match.Groups[1].Value -gt 0
  }
  if ($Workflow -eq 'book_info') {
    $match = [regex]::Match($OutputSummary, '^book_info:rules=(\d+);resolved=(\d+);selectors=[^;]*;body=\d+:[A-Za-z0-9_]+;downloads=\d+$')
    return $match.Success -and [int]$match.Groups[1].Value -gt 0 -and [int]$match.Groups[2].Value -gt 0
  }
  if ($Workflow -eq 'toc') {
    $match = [regex]::Match($OutputSummary, '^toc:(\d+)$')
    return $match.Success -and [int]$match.Groups[1].Value -gt 0
  }
  if ($Workflow -eq 'content') {
    $match = [regex]::Match(
      $OutputSummary,
      '^content:pages=(\d+);fragments=(\d+);chars=(\d+);replace=(?:applied|none);presentation=readable$'
    )
    return $match.Success -and [int]$match.Groups[1].Value -gt 0 -and
      [int]$match.Groups[2].Value -gt 0 -and [int]$match.Groups[3].Value -gt 0
  }
  return $false
}

function Test-RequiredWorkflowTraceSet {
  param([object[]]$Records, [string[]]$RequiredWorkflows)
  foreach ($workflow in $RequiredWorkflows) {
    $record = @($Records | Where-Object { $_.workflow -eq $workflow } | Select-Object -Last 1)
    if ($record.Count -ne 1) {
      return [pscustomobject]@{ passed = $false; workflow = $workflow; reason = 'missing' }
    }
    if ($record[0].errorCode -ne 'none' -or $record[0].statusCode -lt 200 -or $record[0].statusCode -ge 400) {
      if ($record[0].errorCode -eq 'unsupported_api') {
        return [pscustomobject]@{ passed = $false; workflow = $workflow; reason = 'unsupported_api' }
      }
      return [pscustomobject]@{ passed = $false; workflow = $workflow; reason = 'transport_or_rule_failure' }
    }
    if (-not (Test-WorkflowOutputSummary -Workflow $workflow -OutputSummary $record[0].outputSummary)) {
      return [pscustomobject]@{ passed = $false; workflow = $workflow; reason = 'empty_output_summary' }
    }
  }
  return [pscustomobject]@{ passed = $true; workflow = ''; reason = '' }
}

function Get-WorkflowExceptionCategory {
  param([System.Management.Automation.ErrorRecord]$ErrorRecord)
  $message = ''
  if ($null -ne $ErrorRecord.Exception) {
    $message = [string]$ErrorRecord.Exception.Message
  }
  if ($message.Contains('书籍详情没有完成目录加载')) {
    return 'detail_or_toc_ui'
  }
  if ($message.Contains('阅读器仍然收到原始 HTML')) {
    return 'reader_html_not_normalized'
  }
  if ($message.Contains('阅读器没有可见正文节点')) {
    return 'reader_empty'
  }
  if ($message.Contains('等待真机 UI 文本超时')) {
    return 'ui_timeout'
  }
  if ($message.Contains('HDC 执行失败')) {
    return 'device_command_failure'
  }
  return 'other_workflow_exception'
}

function Get-CandidateTraceSnapshot {
  param([string]$SourceName)
  try {
    Return-ToSourceManagement | Out-Null
    if (-not (Test-EnableFullV2AndFilterSource -SourceName $SourceName)) {
      return [pscustomobject]@{ state = 'not_ready'; records = @() }
    }
    # Navigation re-entry refreshes persisted trace summaries asynchronously.
    # Wait for the target card's own trace nodes instead of sampling the first
    # frame or accepting another filtered card's status.
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(15)
    $latestRecords = @()
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
      $layout = Get-UiLayout
      $latestRecords = @(Get-V2TraceRecordsFromLayout -Layout $layout -SourceName $SourceName)
      if ($latestRecords.Count -gt 0) {
        return [pscustomobject]@{ state = 'captured'; records = $latestRecords }
      }
      Start-Sleep -Milliseconds 600
    }
    return [pscustomobject]@{ state = 'captured'; records = $latestRecords }
  } catch {
    # A trace collection failure is itself a separate, evidence-safe outcome.
    # Do not emit the raw exception because it can contain a page title or a
    # source-specific endpoint.
    return [pscustomobject]@{ state = 'collection_failed'; records = @() }
  }
}

function Add-CandidateTraceFailureCounts {
  param(
    [object[]]$Records,
    [System.Collections.IDictionary]$Counts
  )
  if ($Records.Count -eq 0) {
    $Counts['missing_trace'] = [int]$Counts['missing_trace'] + 1
    return
  }
  foreach ($record in $Records) {
    if ($record.errorCode -eq 'none' -and $record.statusCode -ge 200 -and $record.statusCode -lt 400) {
      if (-not (Test-WorkflowOutputSummary -Workflow $record.workflow -OutputSummary $record.outputSummary)) {
        $Counts['empty_output_summary'] = [int]$Counts['empty_output_summary'] + 1
      }
      continue
    }
    if ($record.errorCode -eq 'unsupported_api') {
      $Counts['unsupported_api'] = [int]$Counts['unsupported_api'] + 1
    } else {
      $Counts['transport_or_rule_failure'] = [int]$Counts['transport_or_rule_failure'] + 1
    }
  }
}

function Write-Utf8Atomic {
  param([string]$Path, [string]$Content)
  $directory = Split-Path -Path $Path -Parent
  if (-not (Test-Path -LiteralPath $directory)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$Path.tmp.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  [System.IO.File]::WriteAllText($temporary, $Content, [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Start-ManxiaApplication {
  Invoke-Hdc -Arguments @('shell', 'aa', 'force-stop', $BundleName) | Out-Null
  Invoke-Hdc -Arguments @('shell', 'aa', 'start', '-a', $AbilityName, '-b', $BundleName, '-m', $ModuleName) | Out-Null
  Start-Sleep -Seconds 2
}

try {
  if (-not (Test-Path -LiteralPath $HdcPath)) {
    throw 'HDC 不存在。'
  }
  [System.IO.Directory]::CreateDirectory($TempRoot) | Out-Null
  $candidateSources = @(Get-RealTextSourceCandidates -PackagePath $SourcePackagePath -PreferredName $PreferredTextSourceName -MaximumCount $MaxCandidateSources)
  if ($candidateSources.Count -eq 0) {
    throw '真实书源包中没有可用于普通文本搜索的候选书源。'
  }
  $script:CandidateSelectionSummary.keywordSetSha256 = Get-KeywordSetSha256
  $uiWorkflowOutputs = $null
  $candidateAttempts = 0
  $candidateAttemptRecords = @()
  $successfulSourceName = ''
  $beforeRestartLayout = $null
  $beforeRestartTraceRecords = @()
  $requiredWorkflows = @('search', 'book_info', 'toc', 'content')
  $candidateTraceRejections = 0
  $candidateFailureCounts = [ordered]@{
    not_ready = 0
    search_empty_or_no_result = 0
    workflow_exception = 0
    detail_or_toc_ui = 0
    reader_html_not_normalized = 0
    reader_empty = 0
    ui_timeout = 0
    device_command_failure = 0
    other_workflow_exception = 0
    missing_trace = 0
    trace_collection_failure = 0
    unsupported_api = 0
    transport_or_rule_failure = 0
    empty_output_summary = 0
  }
  foreach ($candidateSource in $candidateSources) {
    $sourceName = [string]$candidateSource.sourceName
    $sourceHash = [string]$candidateSource.sourceHash
    for ($keywordIndex = 0; $keywordIndex -lt $script:SearchKeywords.Count; $keywordIndex++) {
      $keyword = [string]$script:SearchKeywords[$keywordIndex]
      $candidateAttempts++
      Write-Output "STAGE7_UI_CANDIDATE attempt=$candidateAttempts"
      $attemptRecord = [pscustomobject][ordered]@{
        sourceHash = $sourceHash
        keywordIndex = $keywordIndex
        outcome = 'started'
        traceState = 'not_collected'
      }
      Start-ManxiaApplication
      Navigate-ToSourceManagement
      if (-not (Test-EnableFullV2AndFilterSource -SourceName $sourceName)) {
        # Capability readiness does not depend on the keyword.  Do not issue
        # the remaining queries for this source; advance to the next source.
        $candidateFailureCounts.not_ready++
        $attemptRecord.outcome = 'not_ready'
        $attemptRecord.traceState = 'not_ready'
        $candidateAttemptRecords += $attemptRecord
        break
      }
      try {
        $candidateResult = Open-SourceSearchAndRead -SourceName $sourceName -SearchKeyword $keyword
      } catch {
        $candidateFailureCounts.workflow_exception++
        $exceptionCategory = Get-WorkflowExceptionCategory -ErrorRecord $_
        $candidateFailureCounts[$exceptionCategory] = [int]$candidateFailureCounts[$exceptionCategory] + 1
        $attemptRecord.outcome = $exceptionCategory
        $snapshot = Get-CandidateTraceSnapshot -SourceName $sourceName
        $attemptRecord.traceState = [string]$snapshot.state
        if ($snapshot.state -eq 'not_ready') {
          $candidateFailureCounts.not_ready++
        } elseif ($snapshot.state -eq 'collection_failed') {
          $candidateFailureCounts.trace_collection_failure++
        } else {
          Add-CandidateTraceFailureCounts -Records @($snapshot.records) -Counts $candidateFailureCounts
        }
        $candidateAttemptRecords += $attemptRecord
        Write-Output "STAGE7_UI_CANDIDATE_WORKFLOW_REJECTED reason=$exceptionCategory"
        continue
      }
      if ($null -ne $candidateResult) {
        $snapshot = Get-CandidateTraceSnapshot -SourceName $sourceName
        if ($snapshot.state -eq 'not_ready') {
          $candidateTraceRejections++
          $candidateFailureCounts.not_ready++
          $attemptRecord.outcome = 'not_ready_after_return'
          $attemptRecord.traceState = 'not_ready'
          $candidateAttemptRecords += $attemptRecord
          Write-Output 'STAGE7_UI_CANDIDATE_TRACE_REJECTED workflow=source;reason=not_ready_after_return'
          break
        }
        if ($snapshot.state -eq 'collection_failed') {
          $candidateTraceRejections++
          $candidateFailureCounts.trace_collection_failure++
          $attemptRecord.outcome = 'trace_collection_failure'
          $attemptRecord.traceState = 'collection_failed'
          $candidateAttemptRecords += $attemptRecord
          Write-Output 'STAGE7_UI_CANDIDATE_TRACE_REJECTED workflow=source;reason=trace_collection_failure'
          continue
        }
        $candidateManagementLayout = Get-UiLayout
        $candidateTraceRecords = @($snapshot.records)
        $candidateTraceCheck = Test-RequiredWorkflowTraceSet -Records $candidateTraceRecords -RequiredWorkflows $requiredWorkflows
        if (-not [bool]$candidateTraceCheck.passed) {
          $candidateTraceRejections++
          Add-CandidateTraceFailureCounts -Records $candidateTraceRecords -Counts $candidateFailureCounts
          $attemptRecord.outcome = "trace_$($candidateTraceCheck.reason)"
          $attemptRecord.traceState = 'captured'
          $candidateAttemptRecords += $attemptRecord
          Write-Output "STAGE7_UI_CANDIDATE_TRACE_REJECTED workflow=$($candidateTraceCheck.workflow);reason=$($candidateTraceCheck.reason)"
          continue
        }
        $attemptRecord.outcome = 'complete'
        $attemptRecord.traceState = 'captured'
        $candidateAttemptRecords += $attemptRecord
        $uiWorkflowOutputs = $candidateResult
        $successfulSourceName = $sourceName
        $beforeRestartLayout = $candidateManagementLayout
        $beforeRestartTraceRecords = $candidateTraceRecords
        break
      }
      $candidateFailureCounts.search_empty_or_no_result++
      $attemptRecord.outcome = 'search_empty_or_no_result'
      $snapshot = Get-CandidateTraceSnapshot -SourceName $sourceName
      $attemptRecord.traceState = [string]$snapshot.state
      if ($snapshot.state -eq 'not_ready') {
        $candidateFailureCounts.not_ready++
      } elseif ($snapshot.state -eq 'collection_failed') {
        $candidateFailureCounts.trace_collection_failure++
      } else {
        Add-CandidateTraceFailureCounts -Records @($snapshot.records) -Counts $candidateFailureCounts
      }
      $candidateAttemptRecords += $attemptRecord
    }
    if ($null -ne $uiWorkflowOutputs) {
      break
    }
  }
  if ($null -eq $uiWorkflowOutputs) {
    $failureSummary = "not_ready=$($candidateFailureCounts.not_ready);search_empty_or_no_result=$($candidateFailureCounts.search_empty_or_no_result);workflow_exception=$($candidateFailureCounts.workflow_exception);detail_or_toc_ui=$($candidateFailureCounts.detail_or_toc_ui);reader_html_not_normalized=$($candidateFailureCounts.reader_html_not_normalized);reader_empty=$($candidateFailureCounts.reader_empty);ui_timeout=$($candidateFailureCounts.ui_timeout);device_command_failure=$($candidateFailureCounts.device_command_failure);other_workflow_exception=$($candidateFailureCounts.other_workflow_exception);missing_trace=$($candidateFailureCounts.missing_trace);trace_collection_failure=$($candidateFailureCounts.trace_collection_failure);unsupported_api=$($candidateFailureCounts.unsupported_api);transport_or_rule_failure=$($candidateFailureCounts.transport_or_rule_failure);empty_output_summary=$($candidateFailureCounts.empty_output_summary)"
    $diagnostic = [pscustomobject][ordered]@{
      schemaVersion = 2
      generatedAt = Get-ExecutionTimestamp
      sourcePackageSha256 = $SourcePackageSha256
      policy = 'v2_full_cutover'
      automation = 'hdc_uitest'
      outcome = 'no_complete_user_path'
      candidateAttempts = $candidateAttempts
      candidateSelection = $script:CandidateSelectionSummary
      candidateSelectorVersion = $CandidateSelectorVersion
      candidateAttemptRecords = $candidateAttemptRecords
      candidateFailures = $candidateFailureCounts
      traceRejections = $candidateTraceRejections
    }
    Write-Utf8Atomic -Path $DiagnosticEvidencePath -Content ($diagnostic | ConvertTo-Json -Depth 8)
    throw "重启前缺少成功的 V2 用户路径：真实文本书源候选矩阵未产生完整 V2 用户路径（已自动尝试 $candidateAttempts 组安全查询，trace 拒绝=$candidateTraceRejections；$failureSummary）。"
  }
  Write-Output 'STAGE7_UI_TRACE_BEFORE_RESTART'
  Start-ManxiaApplication
  Navigate-ToSourceManagement
  if (-not (Test-EnableFullV2AndFilterSource -SourceName $successfulSourceName)) {
    throw '已选中的真机候选在重启后不再处于 V2 全量执行状态。'
  }
  Write-Output 'STAGE7_UI_TRACE_AFTER_RESTART'
  $restoredSnapshot = Get-CandidateTraceSnapshot -SourceName $successfulSourceName
  if ([string]$restoredSnapshot.state -ne 'captured') {
    throw '重启后未能恢复目标书源的 V2 trace 摘要。'
  }
  $traceRecords = @($restoredSnapshot.records)
  $evidenceWorkflows = @()
  foreach ($workflow in $requiredWorkflows) {
    $record = @($traceRecords | Where-Object { $_.workflow -eq $workflow } | Select-Object -Last 1)
    if ($record.Count -ne 1 -or $record[0].errorCode -ne 'none' -or $record[0].statusCode -lt 200 -or $record[0].statusCode -ge 400) {
      throw "重启后缺少成功的 V2 $workflow trace。"
    }
    $uiOutput = [bool]$uiWorkflowOutputs.$workflow
    if (-not $uiOutput) {
      throw "真实用户路径没有为 $workflow 产生普通界面输出。"
    }
    if (-not (Test-WorkflowOutputSummary -Workflow $workflow -OutputSummary $record[0].outputSummary)) {
      throw "真实用户路径的 $workflow V2 trace 没有可验证的非空输出摘要。"
    }
    $evidenceWorkflows += [pscustomobject][ordered]@{
      workflow = $record[0].workflow
      transport = $record[0].transport
      statusCode = $record[0].statusCode
      errorCode = $record[0].errorCode
      outputKind = 'ui_and_trace_verified'
    }
  }
  $evidence = [pscustomobject][ordered]@{
    schemaVersion = 4
    generatedAt = Get-ExecutionTimestamp
    sourcePackageSha256 = $SourcePackageSha256
    policy = 'v2_full_cutover'
    automation = 'hdc_uitest'
    # The phone exposes Book Source Management as an embedded page below the
    # MainMenuPage NavDestination, so a focused NavDestination alone cannot
    # distinguish it from its retained source-search sibling.  Every action is
    # instead gated by its exact page marker and a header-scoped control.
    uiScope = 'explicit_page_marker_and_header_scope'
    traceEvidence = 'persisted_workflow_summary'
    candidateAttempts = $candidateAttempts
    candidateSelection = $script:CandidateSelectionSummary
    candidateFailures = $candidateFailureCounts
    readerPresentation = 'readable'
    tracePersistence = [pscustomobject][ordered]@{
      beforeRestart = $true
      afterRestart = $true
    }
    workflows = $evidenceWorkflows
  }
  Write-Utf8Atomic -Path $EvidencePath -Content ($evidence | ConvertTo-Json -Depth 6)
  Write-Output 'STAGE7_DEVICE_EVIDENCE_READY'
} finally {
  if (Test-Path -LiteralPath $TempRoot) {
    $tempBase = [System.IO.Path]::GetTempPath()
    if ($TempRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
      Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}
