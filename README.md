# HCI.Registrationinfo
Collects Azure Local registration, connection, IMDS, event log, and Azure Arc configuration data.

At the start of collection, the module enables `Microsoft-AzureStack-HCI/Debug` on every cluster node.
It then opens a dedicated Windows PowerShell window and pauses collection while the user reproduces the registration or repair-registration failure.
The reproduction window records a transcript and writes registration logs into the bundle directory.
Run `Complete-HCIRegistrationRepro` in that window after the attempt to resume collection.


**Installation of the module:**

Download with wget:

`wget https://raw.githubusercontent.com/Mihaly7/HCI.Registrationinfo/main/HCI.Registration.psm1 -OutFile HCI.Registration.psm1`

Install the module:

`Import-Module .\HCI.Registration.psm1`

Get the readme of the command:

`Get-Help Collect-HCIRegistrationInfo -full`

Run Data collection

`Collect-HciRegistrationInfo`

If `AzStackHci.EnvironmentChecker` is already installed, connectivity validation runs by default.
If it is missing, the collector records that the check was skipped and continues without installing anything.
