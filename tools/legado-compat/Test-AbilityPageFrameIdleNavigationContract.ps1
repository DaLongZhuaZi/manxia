[CmdletBinding()]
param(
  [string]$RepositoryRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}

function Read-Utf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)

  $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
  return [System.IO.File]::ReadAllText($Path, $utf8)
}

function Assert-Contract {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Message
  )

  if (-not $Condition) {
    throw "Ability page frame-idle navigation contract failed: $Message"
  }
}

function Get-BlockAt {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Signature,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $signatureStart = $Text.IndexOf($Signature)
  Assert-Contract ($signatureStart -ge 0) "$Description must exist."

  $blockStart = $Text.IndexOf('{', $signatureStart)
  Assert-Contract ($blockStart -ge 0) "$Description must have an opening block."

  $depth = 0
  for ($index = $blockStart; $index -lt $Text.Length; $index += 1) {
    $character = $Text[$index]
    if ($character -eq '{') {
      $depth += 1
      continue
    }
    if ($character -eq '}') {
      $depth -= 1
      if ($depth -eq 0) {
        return $Text.Substring($signatureStart, $index - $signatureStart + 1)
      }
    }
  }

  throw "Ability page frame-idle navigation contract failed: $Description has no closing block."
}

function Get-LiteralCount {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Value
  )

  return ([regex]::Matches($Text, [regex]::Escape($Value))).Count
}

$contracts = @(
  [PSCustomObject]@{
    PageName = 'NovelReaderAbilityPage'
    RelativePath = 'entry\src\main\ets\pages\NovelReaderAbilityPage.ets'
    CallbackClass = 'NovelReaderNavigationFrameCallback'
    SchedulerSignature = 'private scheduleInitialReaderOpen(): void'
    OpenSignature = 'private openInitialReader(): boolean'
    OpenCallToken = 'this.openInitialReader('
    SchedulerCall = 'this.scheduleInitialReaderOpen();'
    OpenedFlag = 'hasOpenedReader'
    ScheduleFlag = 'hasScheduledInitialReaderOpen'
    StablePathStack = 'private pathStack: NavPathStack = new NavPathStack();'
    RefreshReplaceSignature = ''
  },
  [PSCustomObject]@{
    PageName = 'EBookReaderAbilityPage'
    RelativePath = 'entry\src\main\ets\pages\EBookReaderAbilityPage.ets'
    CallbackClass = 'EBookReaderNavigationFrameCallback'
    SchedulerSignature = 'private scheduleInitialReaderOpen(): void'
    OpenSignature = 'private async openInitialReader(scheduleGeneration: number): Promise<void>'
    OpenCallToken = 'this.openInitialReader('
    SchedulerCall = 'this.scheduleInitialReaderOpen();'
    OpenedFlag = 'hasOpenedReader'
    ScheduleFlag = 'hasScheduledInitialReaderOpen'
    StablePathStack = 'private pathStack: NavPathStack = new NavPathStack();'
    RefreshReplaceSignature = ''
  },
  [PSCustomObject]@{
    PageName = 'FileEditorAbilityPage'
    RelativePath = 'entry\src\main\ets\pages\FileEditorAbilityPage.ets'
    CallbackClass = 'FileEditorNavigationFrameCallback'
    SchedulerSignature = 'private scheduleInitialEditorOpen(): void'
    OpenSignature = 'private openInitialEditor(): boolean'
    OpenCallToken = 'this.openInitialEditor('
    SchedulerCall = 'this.scheduleInitialEditorOpen();'
    OpenedFlag = 'hasOpenedEditor'
    ScheduleFlag = 'hasScheduledInitialEditorOpen'
    StablePathStack = 'private pathStack: NavPathStack = new NavPathStack();'
    RefreshReplaceSignature = ''
  },
  [PSCustomObject]@{
    PageName = 'ReadAloudPlayerAbilityPage'
    RelativePath = 'entry\src\main\ets\pages\ReadAloudPlayerAbilityPage.ets'
    CallbackClass = 'ReadAloudPlayerNavigationFrameCallback'
    SchedulerSignature = 'private scheduleInitialPlayerOpen(): void'
    OpenSignature = 'private openInitialPlayer(): boolean'
    OpenCallToken = 'this.openInitialPlayer('
    SchedulerCall = 'this.scheduleInitialPlayerOpen();'
    OpenedFlag = 'hasOpenedPlayer'
    ScheduleFlag = 'hasScheduledInitialPlayerOpen'
    StablePathStack = 'private pathStack: NavPathStack = new NavPathStack();'
    RefreshReplaceSignature = 'private replacePlayerParams(source: string): void'
  },
  [PSCustomObject]@{
    PageName = 'RemoteControlAbilityPage'
    RelativePath = 'entry\src\main\ets\pages\RemoteControlAbilityPage.ets'
    CallbackClass = 'RemoteControlNavigationFrameCallback'
    SchedulerSignature = 'private scheduleInitialRemoteControlOpen(): void'
    OpenSignature = 'private openInitialRemoteControl(): boolean'
    OpenCallToken = 'this.openInitialRemoteControl('
    SchedulerCall = 'this.scheduleInitialRemoteControlOpen();'
    OpenedFlag = 'hasOpenedRemoteControl'
    ScheduleFlag = 'hasScheduledInitialRemoteControlOpen'
    StablePathStack = "@Provide('NavPathStack') pathStack: NavPathStack = new NavPathStack();"
    RefreshReplaceSignature = 'private replaceRemoteControlParams(source: string): void'
  },
  [PSCustomObject]@{
    PageName = 'SourceDetailAbilityPage'
    RelativePath = 'entry\src\main\ets\pages\SourceDetailAbilityPage.ets'
    CallbackClass = 'SourceDetailNavigationFrameCallback'
    SchedulerSignature = 'private scheduleInitialSourceDetailOpen(): void'
    OpenSignature = 'private openInitialSourceDetail(): boolean'
    OpenCallToken = 'this.openInitialSourceDetail('
    SchedulerCall = 'this.scheduleInitialSourceDetailOpen();'
    OpenedFlag = 'hasOpenedSourceDetail'
    ScheduleFlag = 'hasScheduledInitialSourceDetailOpen'
    StablePathStack = "@Provide('NavPathStack') pathStack: NavPathStack = new NavPathStack();"
    RefreshReplaceSignature = ''
  }
)

$results = @()
foreach ($contract in $contracts) {
  $pagePath = Join-Path $RepositoryRoot $contract.RelativePath
  Assert-Contract (Test-Path -LiteralPath $pagePath -PathType Leaf) "$($contract.PageName) source file must exist."
  $pageText = Read-Utf8Text -Path $pagePath

  Assert-Contract ($pageText.Contains("import { FrameCallback, UIContext } from '@kit.ArkUI';")) "$($contract.PageName) must import FrameCallback and UIContext."
  Assert-Contract ($pageText.Contains("class $($contract.CallbackClass) extends FrameCallback")) "$($contract.PageName) must use its typed FrameCallback."
  Assert-Contract ($pageText.Contains($contract.StablePathStack)) "$($contract.PageName) must retain one stable NavPathStack controller."
  Assert-Contract (-not [regex]::IsMatch($pageText, '@State\s+(?:private\s+)?pathStack\b')) "$($contract.PageName) must not decorate NavPathStack as component state."
  Assert-Contract (-not $pageText.Contains('onDidBuild(): void')) "$($contract.PageName) must not use onDidBuild as a navigation boundary."
  Assert-Contract (-not [regex]::IsMatch($pageText, '\b(any|unknown|ESObject)\b')) "$($contract.PageName) must not introduce forbidden dynamic ArkTS types."

  $frameCallbackText = Get-BlockAt -Text $pageText -Signature "class $($contract.CallbackClass) extends FrameCallback" -Description "$($contract.PageName) typed FrameCallback"
  Assert-Contract ($frameCallbackText.Contains('onIdle(_timeLeftInNano: number): void')) "$($contract.PageName) FrameCallback must commit only when the frame is idle."
  Assert-Contract ($frameCallbackText.Contains('if (this.hasRun)')) "$($contract.PageName) FrameCallback must reject duplicate idle execution."
  Assert-Contract ($frameCallbackText.Contains('this.hasRun = true;')) "$($contract.PageName) FrameCallback must mark the idle callback as consumed."
  Assert-Contract ($frameCallbackText.Contains('this.callback();')) "$($contract.PageName) FrameCallback must invoke its typed callback."

  $appearText = Get-BlockAt -Text $pageText -Signature 'aboutToAppear(): void' -Description "$($contract.PageName) aboutToAppear"
  $showText = Get-BlockAt -Text $pageText -Signature 'onPageShow(): void' -Description "$($contract.PageName) onPageShow"
  $disappearText = Get-BlockAt -Text $pageText -Signature 'aboutToDisappear(): void' -Description "$($contract.PageName) aboutToDisappear"
  $schedulerText = Get-BlockAt -Text $pageText -Signature $contract.SchedulerSignature -Description "$($contract.PageName) frame-idle scheduler"
  $openText = Get-BlockAt -Text $pageText -Signature $contract.OpenSignature -Description "$($contract.PageName) initial opener"

  Assert-Contract ($appearText.Contains('this.isPageActive = true;')) "$($contract.PageName) aboutToAppear must activate the page scope."
  Assert-Contract ($appearText.Contains($contract.SchedulerCall)) "$($contract.PageName) aboutToAppear must schedule, rather than synchronously commit, initial navigation."
  Assert-Contract (-not $appearText.Contains($contract.OpenCallToken)) "$($contract.PageName) aboutToAppear must not directly open the initial destination."
  Assert-Contract (-not $appearText.Contains('pushPathByName(')) "$($contract.PageName) aboutToAppear must not mutate NavPathStack."
  Assert-Contract (-not $appearText.Contains('setTimeout(')) "$($contract.PageName) aboutToAppear must not use a timer as a render boundary."

  Assert-Contract ($showText.Contains('this.isPageActive = true;')) "$($contract.PageName) onPageShow must reactivate the page scope."
  Assert-Contract ($showText.Contains($contract.SchedulerCall)) "$($contract.PageName) onPageShow must route recovery through the frame-idle scheduler."
  Assert-Contract (-not $showText.Contains($contract.OpenCallToken)) "$($contract.PageName) onPageShow must not directly open the initial destination."
  Assert-Contract (-not $showText.Contains('pushPathByName(')) "$($contract.PageName) onPageShow must not mutate NavPathStack."
  Assert-Contract (-not $showText.Contains('setTimeout(')) "$($contract.PageName) onPageShow must not use a timer as a render boundary."

  Assert-Contract ($disappearText.Contains('this.isPageActive = false;')) "$($contract.PageName) aboutToDisappear must invalidate deferred navigation."
  Assert-Contract ($disappearText.Contains('this.navigationScheduleGeneration += 1;')) "$($contract.PageName) aboutToDisappear must invalidate stale callbacks."
  Assert-Contract ($disappearText.Contains("this.$($contract.ScheduleFlag) = false;")) "$($contract.PageName) aboutToDisappear must release the scheduling guard."
  Assert-Contract ($disappearText.Contains('this.scheduledFrameCallback = null;')) "$($contract.PageName) aboutToDisappear must release the retained callback."
  Assert-Contract (-not $disappearText.Contains('pushPathByName(')) "$($contract.PageName) aboutToDisappear must not mutate NavPathStack."
  Assert-Contract (-not $disappearText.Contains('setTimeout(')) "$($contract.PageName) aboutToDisappear must not use a timer as a render boundary."

  Assert-Contract ($schedulerText.Contains('!this.isPageActive')) "$($contract.PageName) scheduler must require an active page."
  Assert-Contract ($schedulerText.Contains("this.$($contract.OpenedFlag)")) "$($contract.PageName) scheduler must guard an existing destination."
  Assert-Contract ($schedulerText.Contains("this.$($contract.ScheduleFlag)")) "$($contract.PageName) scheduler must guard an existing pending callback."
  Assert-Contract ($schedulerText.Contains('const uiContext: UIContext = this.getUIContext();')) "$($contract.PageName) scheduler must use the page UIContext."
  Assert-Contract ($schedulerText.Contains("new $($contract.CallbackClass)")) "$($contract.PageName) scheduler must use the typed FrameCallback."
  Assert-Contract ($schedulerText.Contains('uiContext.postFrameCallback(frameCallback);')) "$($contract.PageName) scheduler must defer to the next frame."
  Assert-Contract ($schedulerText.Contains('scheduleGeneration !== this.navigationScheduleGeneration')) "$($contract.PageName) scheduler must reject stale callbacks."
  Assert-Contract ($schedulerText.Contains('this.scheduledFrameCallback = frameCallback;')) "$($contract.PageName) scheduler must retain the pending callback."
  Assert-Contract ($schedulerText.Contains($contract.OpenCallToken)) "$($contract.PageName) only the frame-idle scheduler may call the initial opener."
  Assert-Contract (-not $schedulerText.Contains('setTimeout(')) "$($contract.PageName) scheduler must not use a timer as a render boundary."

  Assert-Contract (-not $openText.Contains('this.pathStack =')) "$($contract.PageName) initial opener must not replace the stable NavPathStack controller."
  Assert-Contract ([regex]::IsMatch($openText, 'this\.pathStack\.pushPathByName\([\s\S]*?,\s*false\);')) "$($contract.PageName) initial opener must push without animation."
  $pushIndex = $openText.IndexOf('this.pathStack.pushPathByName(')
  $openedIndex = $openText.IndexOf("this.$($contract.OpenedFlag) = true;")
  Assert-Contract (($pushIndex -ge 0) -and ($openedIndex -gt $pushIndex)) "$($contract.PageName) must commit its opened guard after the path is pushed."

  if (-not [string]::IsNullOrWhiteSpace($contract.RefreshReplaceSignature)) {
    $refreshReplaceText = Get-BlockAt -Text $pageText -Signature $contract.RefreshReplaceSignature -Description "$($contract.PageName) refresh replacement"
    $notOpenedGuard = "if (!this.$($contract.OpenedFlag))"
    $notOpenedIndex = $refreshReplaceText.IndexOf($notOpenedGuard)
    $refreshScheduleIndex = $refreshReplaceText.IndexOf($contract.SchedulerCall)
    $guardReturnIndex = $refreshReplaceText.IndexOf('return;', $refreshScheduleIndex)
    $replaceIndex = $refreshReplaceText.IndexOf('replacePathByName(')
    Assert-Contract ($notOpenedIndex -ge 0) "$($contract.PageName) refresh replacement must detect an unopened destination."
    Assert-Contract ($refreshScheduleIndex -gt $notOpenedIndex) "$($contract.PageName) refresh replacement must schedule the initial destination when unopened."
    Assert-Contract (($guardReturnIndex -gt $refreshScheduleIndex) -and ($replaceIndex -gt $guardReturnIndex)) "$($contract.PageName) refresh replacement must return before replacing an unopened destination."
  }

  $pushCount = Get-LiteralCount -Text $pageText -Value '.pushPathByName('
  $openCallCount = Get-LiteralCount -Text $pageText -Value $contract.OpenCallToken
  Assert-Contract ($pushCount -eq 1) "$($contract.PageName) permits exactly one initial pushPathByName site."
  Assert-Contract ($openCallCount -eq 1) "$($contract.PageName) permits exactly one initial opener call, inside the frame-idle scheduler."

  $result = [PSCustomObject]@{
    page = $contract.PageName
    frameIdleCallback = $true
    stableNonStateNavPathStack = $true
    lifecycleDefersNavigation = $true
    staleCallbackInvalidation = $true
    pushSites = $pushCount
    initialOpenCalls = $openCallCount
  }
  $results += $result
}

[PSCustomObject]@{
  status = 'passed'
  pages = $results
  verifiedPageCount = $results.Count
} | ConvertTo-Json -Depth 4 -Compress
