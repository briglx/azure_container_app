"""Azure Function App with Event Grid trigger to check for file existence in Blob Storage."""

import asyncio
import json
import logging
import os
from pathlib import Path

import azure.functions as func
from azure.storage.blob.aio import BlobServiceClient

app = func.FunctionApp()


logger = logging.getLogger(__name__)


async def read_azure_file(connection_string, container_name, file_path):
    """Check if a file exists in Azure Blob Storage."""

    blob_service_client = None
    try:
        blob_service_client = BlobServiceClient.from_connection_string(
            connection_string
        )
        blob_client = blob_service_client.get_blob_client(
            container=container_name, blob=file_path
        )
        raw_contents = await blob_client.download_blob().readall()
        return json.loads(raw_contents)

    except Exception as e:
        logger.error("Error reading blob %s: %s", file_path, e)
        raise

    finally:
        if blob_service_client:
            await blob_service_client.close()


async def read_job_config(container_name, blob_name):
    """Read job config JSON from Azure Blob Storage asynchronously."""
    try:
        connection_string = os.environ.get("APP_STORAGE_CONNECTION")

        # Initialize async BlobServiceClient
        blob_service_client = BlobServiceClient.from_connection_string(
            connection_string
        )

        async with blob_service_client:
            blob_client = blob_service_client.get_blob_client(
                container=container_name, blob=blob_name
            )
            # Read contents as json
            download_stream = await blob_client.download_blob()
            raw_contents = await download_stream.readall()
            return json.loads(raw_contents)

    except Exception as e:  # noqa: BLE001
        logger.error("Error reading blob: %s", str(e))


def parse_event(event):
    """Parse Event Grid event to extract container name and blob name."""
    # Get blob URL from event data
    event_data = event.get_json()
    blob_url = event_data["url"]
    logger.info("Blob URL: %s", blob_url)

    file_parts = blob_url.split(".blob.core.windows.net/")[1].split("/")
    container_name = file_parts[0]
    blob_name = "/".join(file_parts[1:])
    logger.info("Container: %s, Blob: %s", container_name, blob_name)

    return container_name, blob_name


async def check_azure_file(connection_string, container_name, file_path):
    """Check if a file exists in Azure Blob Storage."""

    blob_service_client = None
    try:
        blob_service_client = BlobServiceClient.from_connection_string(
            connection_string
        )
        blob_client = blob_service_client.get_blob_client(
            container=container_name, blob=file_path
        )
        return await blob_client.exists()

    except Exception as e:  # noqa: BLE001
        logger.error("Error checking blob %s: %s", file_path, e)
        return False

    finally:
        if blob_service_client:
            await blob_service_client.close()


async def wait_for_file(connection_string, file_path, timeout, check_interval):
    """Wait for a file to exist, checking periodically."""

    if await check_azure_file(connection_string, "pipeline-files", file_path):
        logger.info("✓ File exists in Azure Blob Storage: %s", file_path)
        return True

    # File doesn't exist, start waiting
    logger.info("✗ File missing: %s", file_path)
    logger.info("  Waiting up to %ss (checking every %ss)...", timeout, check_interval)

    start_time = asyncio.get_event_loop().time()
    attempt = 0

    while asyncio.get_event_loop().time() - start_time < timeout:
        await asyncio.sleep(check_interval)
        attempt += 1
        elapsed = asyncio.get_event_loop().time() - start_time

        logger.info("  Attempt %s at %.1fs for %s...", attempt, elapsed, file_path)

        if Path(file_path).exists():
            logger.info("✓ Found %s", file_path)
            return True
        logger.info("✗ Still missing")

    logger.info("✗ TIMEOUT: File not found after %ss: %s", timeout, file_path)
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
        logger.info("✗ ERROR: Some required files were not found")
        return False

    logger.info("✓ All files found!")
    return True


@app.function_name(name="event_grid_trigger")
@app.event_grid_trigger(arg_name="event")
async def event_grid_test(event: func.EventGridEvent):
    """Azure Function triggered by Event Grid to check for file existence."""
    logger.info("Eventgrid triggered")

    default_timeout = 10  # Total timeout in seconds
    default_check_interval = 2  # Check every 10 seconds

    result_str = json.dumps(
        {
            "id": event.id,
            "data": event.get_json(),
            "topic": event.topic,
            "subject": event.subject,
            "event_type": event.event_type,
        }
    )

    logger.info("Python EventGrid trigger processed an event: %s", result_str)

    connection_string = os.environ.get("APP_STORAGE_CONNECTION")
    if not connection_string:
        logger.error("APP_STORAGE_CONNECTION environment variable not found")

    timeout = int(os.environ.get("FILE_CHECK_TIMEOUT", default_timeout))
    check_interval = int(os.environ.get("FILE_CHECK_INTERVAL", default_check_interval))

    # Parse event data
    container_name, job_config_file_name = parse_event(event)

    # Read job config from blob
    data = await read_job_config(container_name, job_config_file_name)
    logger.info("Job config data: %s", data)

    file_names = data.get("files", [])
    logger.info("Files to check: %s", file_names)
    all_found = await check_all_files(
        connection_string, file_names, timeout, check_interval
    )

    if all_found:
        logger.info("All required files are present. Proceeding with processing...")
