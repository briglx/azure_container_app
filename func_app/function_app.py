import logging
import os

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
