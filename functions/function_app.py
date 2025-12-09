import logging
import os
import json

import azure.functions as func
from azure.storage.blob import BlobServiceClient

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


def process_blob_content(text_content, event_data):
    """Process the blob content based on your requirements"""
    logging.info(f"Processing blob: {event_data.get('subject', 'unknown')}")
    logging.info(f"Text content: {text_content}")
    

@app.function_name(name="event_grid_trigger")
@app.event_grid_trigger(arg_name="event")
def event_grid_test(event: func.EventGridEvent):
    logging.info(f"Eventgrid triggered")
    result = json.dumps({
        'id': event.id,
        'data': event.get_json(),
        'topic': event.topic,
        'subject': event.subject,
        'event_type': event.event_type,
    })

    logging.info('Python EventGrid trigger processed an event: %s', result)

    # Read file contents
    blob_url = result['data']['url']   
    logging.info(f"Blob URL: {blob_url}")

    # Open the blob and read contents
    try:
        connection_string = os.environ.get('APP_STORAGE_CONNECTION')
        if not connection_string:
            logging.error("APP_STORAGE_CONNECTION environment variable not found")
            return
        
        # Create blob client from connection string
        blob_service_client = BlobServiceClient.from_connection_string(connection_string)
        blob_client = blob_service_client.get_blob_client_from_url(blob_url)
        
        # Download and read blob contents
        blob_data = blob_client.download_blob()
        content = blob_data.readall()
        
        # If it's text content (decode to string)
        text_content = content.decode('utf-8')
        logging.info(f"Blob contents (first 500 chars): {text_content[:500]}")
        
        # Process the content as needed
        process_blob_content(text_content, result)
        
    except Exception as e:
        logging.error(f"Error reading blob: {str(e)}")
    
