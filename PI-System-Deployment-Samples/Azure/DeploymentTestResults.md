# PI System Deployment Tests: Viewing Results
To validate a successful deployment, the PI System Deployment Tests are run on the remote desktop machine at the conclusion of a successful deployment. The tests are skipped if the deployment failed.

In order to connect to the remote desktop machine, you will need to ensure that the remote desktop machine can receive RDP requests from your public IP address. After determining your public IP address, log in to the [Azure Portal](https://portal.azure.com). **You must be logged in as the same user account which initiated the deployment, or you will not be able to access account passwords.** 

From the Azure portal: 
1. Select "Virtual Machines" from the list of services on the lefthand menu bar. If "Virtual Machines" does not appear in the list, you can search for it using the search bar on the top of the screen.
2. Locate the "All resource groups" dropdown in and expand the dropdown menu.
3. De-select all resource groups by ensuring that the "Select all" checkbox at the top of the menu is **unchecked**.
4. Locate the resource group which you used for the deployment and select the checkbox next to its name.
5. Click outside of the dropdown menu and wait a moment for the screen to update so that it only shows virutal machines for your resource group.
6. Locate the RDS machine in the list. By default, it will be named `ds-rds-vm0`. Click on the name of the machine.
7. Navigate to "Networking" under "Settings".
8. Click the button to "Add inbound port rule".
9. Specify the "Source" for your rule to "IP Address". After you select "IP Address", the options will change.
10. Under "Source IP address/CIDR ranges", enter your public IP address followed by `/32`. This will only allow traffic from your public IP address.
11. Change the "Destination port ranges" to the value `3389`.
12. Change the "Name" to something meaningful, for example "RDP".
13. Click the "Add" button. Wait a moment for Azure to create the rule. The tab will close automatically once the rule is created.
14. Return to the "Overview" tab for the VM. 
15. Click "Connect". Do not change any default settings. Click "Download RDP File".
16. Before connecting to the VM you will need to look up the password. To do this, go to the "Key vaults" service in Azure, either from the left hand menu or the top search area.
17. Filter the resource group to only the resource group used for your deployment, following steps 2-5.
18. Only one key vault should appear. Click on its name.
19. Navigate to "Secrets" under "Settings".
20. Locate the entry for "ds-admin". This is the domain admin account; the other account names listed here are domain service accounts. Click on the "ds-admin" item.
21. Under "Current Version" there is a GUID, click on this.
22. On the details page for this secret version, locate the area at the bottom with the header "Secret". Optionally, you can choose to "Show Secret Value" to view the text of the password, however you will notice it is a long and complicated string. You do **not** need to have the secret value visible for the next step. 
23. Click the "Copy to Clipboard" button to the right of the secret value. If you have decided to show the secret value it will be a random string of letters, numbers, and symbols; if you have not decided to show the secret value, it will show as a long line of asterisks. The "Copy to Clipboard" button copies the actual value regardless of whether it is currently visible.
24. In File Explorer, go to your downloads folder and locate the RDP file downloaded in step 15. Double click on it to initiate the connection.
    > **Tip** You may get an error message when connecting that the remote machine appears to be offline. If this is the case, return to the "Overview" page for the VM. Click "Connect", but before downloading the RDP file change the "IP address" option from "Load balancer public IP address" to "Load balancer DNS name". Do **not** change the port number.
25.  When launching the RDP connection you may get a warning, "The publisher of this remote connection can't be identified." This warning can be safely ignored by clicking "Connect".
26.  Enter the domain admin username and password. Be sure to specify the username with the domain, as in `ds\ds-admin`. You may simply paste the password directly into that field.
27.  Before finalizing the connection to the machine you will likely get a warning about the remote computer's security certificate. This is because the machine uses a self-signed certificate rather than a paid certificate authenticated by a third party. The warning can be safely ignored by clicking "Yes".


Once you have connected to the RDS machine, viewing test results is straightforward. Open the directory `C:\TestResults`. In this directory you should see two files. One of the files will include "PreCheck" at the end of the file name. If this is the only file in the directory, the tests encountered permission or other configuration problems. Double click the file to open it in any web browser and review the errors. The file with a name such as `OSIsoftTests_2019.09.24@11-20-15.html` is the actual test results. Simply double click this file to open the tests and review the results. 