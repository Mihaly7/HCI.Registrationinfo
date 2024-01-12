# HCI.Registrationinfo
Function which updates Az.STACKHCI and all its related modules, collects connection, IMDS, registration and ARC related configurational info and logs.


**Installation of the module:**

Download with wget:

`wget https://raw.githubusercontent.com/Mihaly7/HCI.Registrationinfo/main/HCI.Registration.psm1 -OutFile HCI.Registration.psm1`

Install the module:

`Import-Module .\HCI.Registration.psm1`

Get the readme of the command:

`Get-Help Collect-HCIRegistrationInfo -full`

Run Data collection

`Collect-HciRegistrationInfo `
