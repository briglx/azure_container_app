import logging
import os
import json
import asyncio
import aiofiles

import azure.functions as func
from azure.storage.blob.aio import BlobServiceClient


# APP_STORAGE_CONNECTION = os.getenv("APP_STORAGE_CONNECTION")
# APP_STORAGE_CONTAINER = os.getenv("APP_STORAGE_CONTAINER")
# APP_STORAGE_INPUT_PATH = os.getenv("APP_STORAGE_INPUT_PATH") 
# APP_STORAGE_OUTPUT_PATH = os.getenv("APP_STORAGE_OUTPUT_PATH") 

# blob_trigger_path = f"{APP_STORAGE_CONTAINER}/{APP_STORAGE_INPUT_PATH}"

app = func.FunctionApp()

# @app.blob_trigger(
#         arg_name="myblob", 
#         path=blob_trigger_path,
#         connection="APP_STORAGE_CONNECTION",
#         source="EventGrid", 
#         ) 
# def event_grid_blob_trigger(myblob: func.InputStream):
#     logging.info(f"Python blob trigger function processed blob"
#                 f"Name: {myblob.name}"
#                 f"Blob Size: {myblob.length} bytes")
#     blobName = myblob.name.split("/")[1]
#     logging.info(f"Process file {blobName}...")

#     output_path = f"{APP_STORAGE_CONTAINER}/{APP_STORAGE_OUTPUT_PATH}"
#     logging.info(f"Write processed file to output path: {output_path}")
  

async def read_azure_file(connection_string, container_name, file_path):
    """Check if a file exists in Azure Blob Storage."""

    blob_service_client = None
    try:
        blob_service_client = BlobServiceClient.from_connection_string(connection_string)
        blob_client = blob_service_client.get_blob_client(
            container=container_name, blob=file_path
        )
        raw_contents = await blob_client.download_blob().readall()
        data = json.loads(raw_contents)
        return data
        
    except Exception as e:
        print(f"Error reading blob {file_path}: {e}")
        raise
        
    finally:
        if blob_service_client:
            await blob_service_client.close()

async def read_job_config(container_name, blob_name):
    try:
        connection_string = os.environ.get('APP_STORAGE_CONNECTION')

        # Initialize async BlobServiceClient
        blob_service_client = BlobServiceClient.from_connection_string(connection_string)

        async with blob_service_client:
            blob_client = blob_service_client.get_blob_client(
                container=container_name, blob=blob_name
            )
            # Read contents as json
            download_stream = await blob_client.download_blob()
            raw_contents = await download_stream.readall()
            data = json.loads(raw_contents)

        return data
    except Exception as e:
        logging.error(f"Error reading blob: {str(e)}")


def parse_event(event):
    # Get blob URL from event data
    event_data = event.get_json()
    blob_url = event_data['url']   
    logging.info(f"Blob URL: {blob_url}")

    file_parts = blob_url.split(".blob.core.windows.net/")[1].split("/")
    container_name = file_parts[0]
    blob_name = "/".join(file_parts[1:])
    logging.info(f"Container: {container_name}, Blob: {blob_name}")

    return container_name, blob_name

async def check_azure_file(connection_string, container_name, file_path):
    """Check if a file exists in Azure Blob Storage."""

    blob_service_client = None
    try:
        blob_service_client = BlobServiceClient.from_connection_string(connection_string)
        blob_client = blob_service_client.get_blob_client(
            container=container_name, blob=file_path
        )
        exists = await blob_client.exists()
        return exists
        
    except Exception as e:
        print(f"Error checking blob {file_path}: {e}")
        return False
        
    finally:
        if blob_service_client:
            await blob_service_client.close()
 
async def wait_for_file(connection_string, file_path, timeout, check_interval):
    """Wait for a file to exist, checking periodically."""
        
    if await check_azure_file(connection_string, "pipeline-files", file_path):
        print(f"✓ File exists in Azure Blob Storage: {file_path}")
        return True
    
    # File doesn't exist, start waiting
    print(f"✗ File missing: {file_path}")
    print(f"  Waiting up to {timeout}s (checking every {check_interval}s)...")
    
    start_time = asyncio.get_event_loop().time()
    attempt = 0
    
    while asyncio.get_event_loop().time() - start_time < timeout:
        await asyncio.sleep(check_interval)
        attempt += 1
        elapsed = asyncio.get_event_loop().time() - start_time
        
        print(f"  Attempt {attempt} at {elapsed:.1f}s for {file_path}...", end=" ")
        
        if os.path.exists(file_path):
            print(f"✓ Found {file_path}")
            return True
        else:
            print(f"✗ Still missing")
    
    print(f"✗ TIMEOUT: File not found after {timeout}s: {file_path}")
    return False

async def check_all_files(connection_string, file_names, timeout, check_interval):
    """Check all files, waiting for each one sequentially."""

    tasks = []

    for file_path in file_names:

        task = wait_for_file(connection_string, file_path, timeout, check_interval)
        tasks.append(task)
    
    results = await asyncio.gather(*tasks, return_exceptions=True)

    all_found = all(results)
    if not all_found:
        print("\n✗ ERROR: Some required files were not found")
        return False
    
    print("\n✓ All files found!")
    return True

@app.function_name(name="event_grid_trigger")
@app.event_grid_trigger(arg_name="event")
async def event_grid_test(event: func.EventGridEvent):
    logging.info(f"Eventgrid triggered")

    default_timeout = 10  # Total timeout in seconds
    default_check_interval = 2  # Check every 10 seconds

    result_str = json.dumps( {
        'id': event.id,
        'data': event.get_json(),
        'topic': event.topic,
        'subject': event.subject,
        'event_type': event.event_type,
    })

    logging.info('Python EventGrid trigger processed an event: %s', result_str)

    connection_string = os.environ.get('APP_STORAGE_CONNECTION')    
    if not connection_string:
        logging.error("APP_STORAGE_CONNECTION environment variable not found")

    timeout = int(os.environ.get('FILE_CHECK_TIMEOUT', default_timeout))
    check_interval = int(os.environ.get('FILE_CHECK_INTERVAL', default_check_interval))

    # Parse event data
    container_name, job_config_file_name = parse_event(event)

    # Read job config from blob
    data = await read_job_config(container_name, job_config_file_name)
    logging.info(f"Job config data: {data}")

    file_names = data.get("files", [])
    logging.info(f"Files to check: {file_names}")
    all_found = await check_all_files(connection_string, file_names, timeout, check_interval)

    if all_found:
        print("All required files are present. Proceeding with processing...")
