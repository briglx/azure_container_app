import logging
import os
import json

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

        # Create blob client from connection string
        blob_service_client = BlobServiceClient.from_connection_string(connection_string)
        blob_client = blob_service_client.get_blob_client(container=container_name, blob=blob_name)

       # Read contents as json
        raw_contents = blob_client.download_blob().readall()
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


@app.function_name(name="event_grid_trigger")
@app.event_grid_trigger(arg_name="event")
async def event_grid_test(event: func.EventGridEvent):
    logging.info(f"Eventgrid triggered")

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

    # Parse event data
    container_name, job_config_file_name = parse_event(event)

    # Read job config from blob
    data = await read_job_config(container_name, job_config_file_name)
    logging.info(f"Job config data: {data}")
