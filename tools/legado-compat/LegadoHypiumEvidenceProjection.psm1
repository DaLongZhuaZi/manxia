Set-StrictMode -Version Latest

function Get-LegadoProjectionProperty {
  param(
    [object]$Object,
    [string]$Name
  )
  if ($null -eq $Object) {
    return $null
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }
  return $property.Value
}

function Get-LegadoProjectionText {
  param(
    [object]$Object,
    [string]$Name
  )
  $value = Get-LegadoProjectionProperty -Object $Object -Name $Name
  if ($null -eq $value) {
    return ''
  }
  return [string]$value
}

function Get-LegadoProjectionTrace {
  param(
    [object]$Attempt,
    [string]$Workflow
  )
  $records = Get-LegadoProjectionProperty -Object $Attempt -Name 'detailTraceRecords'
  if ($null -eq $records) {
    $records = Get-LegadoProjectionProperty -Object $Attempt -Name 'detail_trace_records'
  }
  if ($null -eq $records) {
    return $null
  }
  $matches = @($records | Where-Object { (Get-LegadoProjectionText -Object $_ -Name 'workflow') -eq $Workflow })
  if ($matches.Count -eq 0) {
    return $null
  }
  return $matches[$matches.Count - 1]
}

function Get-LegadoProjectionWorkflowResult {
  param(
    [object]$Attempt,
    [string]$Name
  )
  $results = Get-LegadoProjectionProperty -Object $Attempt -Name 'workflowResults'
  if ($null -eq $results) {
    $results = Get-LegadoProjectionProperty -Object $Attempt -Name 'workflow_results'
  }
  return (Get-LegadoProjectionText -Object $results -Name $Name).Trim().ToLowerInvariant()
}

function Get-LegadoCapturedReadWorkflowAssessments {
  <#
    Consume already persisted read traces before classifying the parent Driver
    process. A reader/UI cleanup failure must not erase independent, complete
    BookInfo/Toc/Content evidence. This function is deliberately pure so the
    contract runner can exercise the exact projection without a device.
  #>
  param(
    [Parameter(Mandatory = $true)]
    [object]$Attempt
  )

  $workflowMap = [ordered]@{
    bookInfo = [pscustomobject][ordered]@{ trace = 'book_info'; result = 'book_info'; expected = 'book_info_metadata_resolved' }
    toc = [pscustomobject][ordered]@{ trace = 'toc'; result = 'toc'; expected = 'toc_nonempty' }
    content = [pscustomobject][ordered]@{ trace = 'content'; result = 'content'; expected = 'content_readable' }
  }
  $assessments = [ordered]@{}
  $passedCount = 0
  $blockedCount = 0
  $failedCount = 0

  foreach ($entry in $workflowMap.GetEnumerator()) {
    $name = [string]$entry.Key
    $definition = $entry.Value
    $trace = Get-LegadoProjectionTrace -Attempt $Attempt -Workflow ([string]$definition.trace)
    $result = Get-LegadoProjectionWorkflowResult -Attempt $Attempt -Name ([string]$definition.result)
    $statusCode = [int](Get-LegadoProjectionText -Object $trace -Name 'statusCode')
    $errorCode = (Get-LegadoProjectionText -Object $trace -Name 'errorCode').Trim().ToLowerInvariant()
    $outputKind = (Get-LegadoProjectionText -Object $trace -Name 'outputKind').Trim().ToLowerInvariant()
    $digest = (Get-LegadoProjectionText -Object $trace -Name 'outputSummarySha256').Trim().ToLowerInvariant()
    $outputLength = [int](Get-LegadoProjectionText -Object $trace -Name 'outputSummaryLength')
    $driverClosed = (Get-LegadoProjectionText -Object $Attempt -Name 'driverClosed').Trim().ToLowerInvariant() -eq 'true'
    if (-not $driverClosed) {
      $driverClosed = (Get-LegadoProjectionText -Object $Attempt -Name 'driver_closed').Trim().ToLowerInvariant() -eq 'true'
    }

    $traceValid = $null -ne $trace -and $statusCode -ge 200 -and $statusCode -lt 400 -and
      $errorCode -eq 'none' -and $outputKind -eq ([string]$definition.expected).ToLowerInvariant() -and
      $digest -match '^[0-9a-f]{64}$' -and $outputLength -gt 0 -and $driverClosed

    $status = 'failed'
    $outcome = 'captured_read_workflow_trace_unusable'
    if ($null -eq $trace) {
      $status = 'blocked'
      $outcome = 'captured_read_workflow_trace_missing'
      $blockedCount++
    } elseif (($statusCode -ge 400) -or $errorCode -in @('http', 'network', 'dns')) {
      $status = 'blocked'
      $outcome = 'captured_read_workflow_external_network_unconfirmed'
      $blockedCount++
    } elseif ($traceValid -and $result -eq 'passed') {
      $status = 'passed'
      $outcome = 'captured_read_workflow_verified'
      $passedCount++
    } else {
      $failedCount++
    }

    $assessments[$name] = [pscustomobject][ordered]@{
      status = $status
      outcome = $outcome
      evidenceDigest = if ($traceValid) { $digest } else { '' }
      tracePresent = $null -ne $trace
      workflowResult = $result
      outputKind = $outputKind
      statusCode = $statusCode
    }
  }

  return [pscustomobject][ordered]@{
    bookInfo = $assessments.bookInfo
    toc = $assessments.toc
    content = $assessments.content
    allPassed = $passedCount -eq 3
    passedCount = $passedCount
    blockedCount = $blockedCount
    failedCount = $failedCount
  }
}

Export-ModuleMember -Function Get-LegadoCapturedReadWorkflowAssessments
