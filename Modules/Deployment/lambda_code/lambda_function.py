import os
import boto3
import ftplib
import tempfile

def lambda_handler(event, context):
    """Pull new video files from FTP and push to S3."""
    ftp_host = os.environ['FTP_HOST']
    ftp_user = os.environ['FTP_USER']
    ftp_pass = os.environ['FTP_PASS']
    bucket_name = os.environ['BUCKET_NAME']

    # Connect to FTP
    ftp = ftplib.FTP(ftp_host)
    ftp.login(ftp_user, ftp_pass)

    # Change directory if needed
    # e.g., ftp.cwd('/videos')  # if your files are in /videos
    # List all files in this folder
    remote_files = ftp.nlst()  # Or ftp.nlst("/videos") if needed

    # Connect to S3
    s3 = boto3.client('s3')

    for filename in remote_files:
        if not filename:
            continue
        # Skip directories if needed, check e.g. if '.' in ftp.size(...) or something
        # Create a temp file for the download
        with tempfile.NamedTemporaryFile() as tmp_file:
            print(f"Downloading {filename} from FTP ...")
            try:
                ftp.retrbinary(f"RETR {filename}", tmp_file.write)
            except Exception as e:
                print(f"Error downloading {filename}: {e}")
                continue

            # Upload to S3
            tmp_file.seek(0)
            print(f"Uploading {filename} to S3 bucket {bucket_name} ...")
            s3.upload_fileobj(tmp_file, bucket_name, filename)

    ftp.quit()
    return {"status": "Success"}
