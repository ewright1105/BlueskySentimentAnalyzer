# Setup Guide for Bluesky Sentiment Analyzer

## Generate GitHub Personal Access Token

1. Go to [https://github.com/](https://github.com/)
2. Click on your profile icon in the top right corner, and navigate to **Settings**.
3. On the navigation bar on the left side, select **Developer settings**.
4. Click **Personal access tokens**, and from the dropdown select **Tokens (classic)**.
5. Click **Generate new token** on the right-hand side of the screen, then select **Generate new token (classic)**.
6. On the create new token screen, provide a note, select **repo** and **admin:repo\_hook**, then click **Generate token**.
7. Copy the generated token and save it securely for later use.

## Create Key Pair (AWS EC2)

1. Navigate to the AWS EC2 Console.
2. On the left-hand side menu, select **Key pairs**.
3. Click **Create key pair**, provide a name, ensure type is **RSA**, and format is **.pem**, then press **Create**.
4. The **.pem** file will automatically download—keep this file secure as you'll need it later.

## Connect to the Instance from the AMI Image

1. We shared an AMI with you. Click the [provided link](https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#ImageDetails:imageId=ami-05d95faecb2b6909b) to navigate to it.
2. Click **Launch instance from AMI**.
3. Give your instance a name, select the key pair you created earlier, ensure a VPC is selected, and click **Launch**.
4. After launching, click **Connect to your instance**.
5. On the **SSH client** tab, copy the connection string at the bottom.

### Connecting Using CloudShell

1. Navigate to the CloudShell console, ensuring you're in the **us-east-1** region.
2. At the top right, click **Actions** and select **Upload file**, then upload the previously downloaded `.pem` file.
3. Run the following command in CloudShell:
   ```bash
   chmod 600 [Your key name].pem
   ```
4. Paste the SSH command copied earlier, changing `root` to `ec2-user`, and press **Enter**. Confirm the connection by entering `yes` when prompted.

## Configure AWS & Run Terraform

1. Ensure you have your AWS Access Key ID and Secret Access Key from your rootkey.csv file. [Refer to this tutorial if needed.](https://docs.aws.amazon.com/general/latest/gr/aws-sec-cred-types.html#access-keys-and-secret-access-keys)
2. In CloudShell, run:
   ```bash
   aws configure
   ```
3. Enter your AWS credentials and set region as `us-east-1`. Skip the output by pressing **Enter**.
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


