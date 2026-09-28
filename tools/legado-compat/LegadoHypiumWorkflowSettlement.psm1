Set-StrictMode -Version Latest

function Get-LegadoHypiumExploreDependencySettlements {
  <#
    Return the terminal transitions required when an Explore-only full-workflow
    attempt cannot select a book target. The function is pure so the exact
    state transition can be verified without a device or a live endpoint.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object]$Record,
    [ValidateSet('blocked', 'failed', 'needs_interaction', 'unsupported_api', 'policy_blocked', 'expected_external')]
    [string]$TerminalStatus = 'blocked',
    [Parameter(Mandatory = $true)]
    [string]$TerminalOutcome
  )

  $workflowsProperty = $Record.PSObject.Properties['workflows']
  if ($null -eq $workflowsProperty -or $null -eq $workflowsProperty.Value) {
    throw 'LEGADO_HYPIUM_WORKFLOWS_MISSING'
  }

  $settlements = [System.Collections.Generic.List[object]]::new()
  foreach ($name in @('bookInfo', 'toc', 'content')) {
    $workflowProperty = $workflowsProperty.Value.PSObject.Properties[$name]
    if ($null -eq $workflowProperty -or $null -eq $workflowProperty.Value) {
      throw "LEGADO_HYPIUM_WORKFLOW_MISSING:$name"
    }
    $statusProperty = $workflowProperty.Value.PSObject.Properties['status']
    $status = if ($null -ne $statusProperty -and $null -ne $statusProperty.Value) {
      [string]$statusProperty.Value
    } else {
      ''
    }
    if ($status -in @('planned', 'running')) {
      [void]$settlements.Add([pscustomobject][ordered]@{
        name = $name
        previousStatus = $status
        status = $TerminalStatus
        outcome = $TerminalOutcome
      })
    }
  }

  return $settlements.ToArray()
}

Export-ModuleMember -Function Get-LegadoHypiumExploreDependencySettlements
