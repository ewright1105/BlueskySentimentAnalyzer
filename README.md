# Setup Guide for Bluesky Sentiment Analyzer

## Generate GitHub Personal Access Token

1. Go to [https://github.com/](https://github.com/)
2. Click on your profile icon in the top right corner, and navigate to **Settings**.
3. On the navigation bar on the left side, select **Developer settings**.
4. Click **Personal access tokens**, and from the dropdown select **Tokens (classic)**.
5. Click **Generate new token** on the right-hand side of the screen, then select **Generate new token (classic)**.
6. On the create new token screen, provide a note, select **repo** and **admin:repo\_hook**, then click **Generate token**.
7. Copy the generated token and save it securely for later use.

### Connecting Using CloudShell

1. Navigate to the CloudShell console, ensuring you're in the **us-east-1** region. If not on **us-east-1**, just keep that in mind as you will need to modify main.tf later on.
2. At the top right, click **Actions** and select **Upload file**, and upload the zip file in the root of this repository. 
3. Unzip the file.This will unpack all the necessary code to build the app, including the main.tf file for the Terraform and all the code/packages for the Lambda functions that make it run. You may remove the original zip file and the **__MACOSX** directory if desired.
4. Next, install terraform using the following commands in order:
```
sudo yum install -y yum-utils
```
```
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
```
```
sudo yum -y install terraform
```

## Configure AWS & Run Terraform

1. Ensure you have your AWS Access Key ID and Secret Access Key from your rootkey.csv file. [Refer to this tutorial if needed.](https://docs.aws.amazon.com/general/latest/gr/aws-sec-cred-types.html#access-keys-and-secret-access-keys)
2. In CloudShell, run:
   ```bash
   aws configure
   ```
3. Enter your AWS credentials and set region as `us-east-1`. Skip the output by pressing **Enter**. (_NOTE: IF YOU WISH TO BUILD ON ANOTHER REGION, OPEN MAIN.TF AND MODIFY THE REGION ON LINE 37_)
4. Initialize Terraform by running:
   ```bash
   terraform init
   ```
5. Copy your GitHub personal access token to the clipboard.
6. Execute Terraform:
   ```bash
   terraform apply
   ```
7. Paste your GitHub token when prompted.

## Building the App

1. Navigate to the AWS Amplify Console.
2. Click on the app titled **team\_8**.
3. If prompted to migrate, close the prompt. Then select the **terraform** branch.
4. Manually trigger **Run job**.
5. Once deployed, open the link provided under **Domain**.

## Using Bluesky Sentiment Analyzer

1. Create an account using a real email address and verify it.
2. Select a topic to monitor (e.g., “Taylor Swift”).
3. Choose an interval length (how often posts are analyzed).
4. Specify the number of intervals to run.
5. Select the number of posts to analyze (max 100).
6. Click **Add Topic**.
7. Select **View Details** to see your data (give it time to populate).
8. Add additional topics as desired. Subtopic data may take longer to calculate initially.
9. Confirm email notifications through your email inbox if desired.

## Cleanup

1. To remove the app, reconnect to your EC2 instance if necessary (refer to **Connecting Using CloudShell** steps above).
2. Run the following Terraform command:
   ```bash
   terraform destroy
   ```
3. Enter any character when prompted for the GitHub personal access token and confirm destruction by entering `yes`.

You're all set! You can now build, use, and destroy the Bluesky Sentiment Analyzer anytime from any machine.


