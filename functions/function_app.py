import logging
import os
import json

import azure.functions as func

APP_STORAGE_CONTAINER = os.getenv("APP_STORAGE_CONTAINER")
APP_STORAGE_INPUT_PATH = os.getenv("APP_STORAGE_INPUT_PATH") 
APP_STORAGE_OUTPUT_PATH = os.getenv("APP_STORAGE_OUTPUT_PATH") 

blob_trigger_path = f"{APP_STORAGE_CONTAINER}/{APP_STORAGE_INPUT_PATH}"

app = func.FunctionApp()

@app.blob_trigger(
        arg_name="myblob", 
        path=blob_trigger_path,
        connection="APP_STORAGE_CONNECTION",
        source="EventGrid", 
        ) 
def event_grid_blob_trigger(myblob: func.InputStream):
    logging.info(f"Python blob trigger function processed blob"
                f"Name: {myblob.name}"
                f"Blob Size: {myblob.length} bytes")
    blobName = myblob.name.split("/")[1]
    logging.info(f"Process file {blobName}...")

    output_path = f"{APP_STORAGE_CONTAINER}/{APP_STORAGE_OUTPUT_PATH}"
    logging.info(f"Write processed file to output path: {output_path}")


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
