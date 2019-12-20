# Testing AWS Script Parameters in Powershell
This guide explains how to use file `TestParameters.ps1`, a powershell script located in the `scripts` folder of this repository. The script is meant as a tool to aid PI System Engineers who are deploying the Master Stack template on AWS. Running this script validates the contents of the S3 buckets the user must create before using the AWS Deployment Sample successfully.

## Instructions
> **Note**
> For best results with the AWS Deployment Samples, it is *highly* recommended that you keep all of your parameters in a text document and copy and paste them between running this script and deployment of the Deployment Sample. 
># **ALL template parameters are case sensitive.**

1. Create S3 buckets in AWS according to the documentation for running the Master Stack Deployment Sample. See other documentation in this repository for instructions.
2. Record the following information about your created S3 buckets. You will need this information to deploy the Deployment Sample template as well as run this script. The parameter names for the script exactly match the parameter names used in the Deployment Sample template.  
   You will need the following information:
   
   Parameter Name | Example | Description
   -- | -- | --
   DSS3BucketName | osisoft-deploySamples | The name of the bucket containing the Deployment Sample files available in this repository. Per AWS limitations, this can contain lowercase letters, numbers, and hyphens.
   DSS3KeyPrefix | deploysample | The name of the root folder containing the Deployment Sample folders `modules`, `scripts`, and `templates`. This can contain mixed case letters (names are case-sensitive), numbers, hyphens (-), and forward slashes (/).
   DSS3BucketRegion | us-west-1 | The region in which your S3 bucket is hosted. The Deployment Sample works best if the buckets are in the same region as your deployed stack, but any region may be used. See [AWS API Gateway documentation](https://docs.aws.amazon.com/general/latest/gr/rande.html) if you are unsure of the designation for your region.
   SetupKitsS3BucketName | osisoft-setupkits | The name of the bucket containing the Setup Kits acquired from OSIsoft, for PI Server and PI Vision. Per AWS limitations, this can contain lowercase letters, numbers, and hyphens.
   SetupKitsS3KeyPrefix | 2018 | The name of the folder containing the folders `PIServer` and `PIVision` which in turn contain their respective installers. This can contain mixed case letters (names are case-sensitive), numbers, hyphens (-), and forward slashes (/).
   SetupKitsS3BucketRegion | us-west-1 | The region in which your S3 bucket is hosted. The Deployment Sample works best if the buckets are in the same region as your deployed stack, but any region may be used. See [AWS API Gateway documentation](https://docs.aws.amazon.com/general/latest/gr/rande.html) if you are unsure of the designation for your region.
   SetupKitsS3PIFileName | PI-Server_2018_.exe | The name of the PI Server setup kit file, in the `PIServer` folder
   SetupKitsS3VisionFileName | PI-Vision_2017 R2-SP1_.exe | The name of the PI Vision setup kit file, in the `PIVision` folder
   TestFileName | Tests-For-Critical-Operations-master.zip | The name of the testing file, in the DSS3KeyPrefix folder

3. Install the AWS Tools for PowerShell on any machine with PowerShell 2.0 or newer. Any Windows machine running Windows 7/Windows Server 2008 R2 or newer comes with an adequate version of PowerShell pre-installed. The AWS Tools for PowerShell can be downloaded from Amazon at the following url: https://aws.amazon.com/powershell/
4. Create an AWS Access Key for the AWS Account that you will use to run the Deployment Sample. This is done in the IAM console under Users > (your username) > Security Credentials. For complete documentation, see [the AWS guide for creating Access Keys](https://docs.aws.amazon.com/powershell/latest/userguide/pstools-appendix-sign-up.html).
5. Configure your PowerShell console to use the Access Key. 
    - Enable a new profile using the following command (substitue your values for AccessKey and SecretKey):

          PS C:\> Set-AWSCredential -AccessKey AKIAIOSFODNN7EXAMPLE -SecretKey wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY -StoreAs MyProfileName
    - If you have previously created an AWS credential profile, enable it using:

          PS C:\> Set-AWSCredential -ProfileName MyProfileName
    - See [Using AWS Credentials](https://docs.aws.amazon.com/powershell/latest/userguide/specifying-your-aws-credentials.html) for more information.
6. In PowerShell, navigate to the `scripts` folder contained within this repository.
7. Execute the script `TestParameters.ps1`. You will be prompted for the values you recorded in step 2. **It is highly recommended that you copy and paste these values, rather than typing out, as the parameters are case sensitive.**
8. The script will first validate the Deployment Sample bucket. The message "DeploySample bucket contents have been verified" will be displayed when all files in the Deployment Sample bucket are verified. 
9. Once the Deployment Sample bucket is verified, the script will validated the Setup Kits bucket. The message "Setup kit bucket contents have been verified" will be displayed when all the files in the Setup Kit bucket are verified.
10. If you see both verification messages, you are ready to continue to the deployment.