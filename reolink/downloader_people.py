import asyncio
import os
from datetime import datetime, timedelta

from reolink_aio.api import Host


# =====================
# CONFIG
# =====================

CAMERA_IP = "192.168.4.103"
USERNAME = "admin"
PASSWORD = "Shiva0587"

CHANNEL = 0

SAVE_DIR = "./person_clips"

# How far back to search
HOURS_BACK = 24


# =====================
# MAIN
# =====================

async def main():

    os.makedirs(SAVE_DIR, exist_ok=True)

    camera = Host(
        CAMERA_IP,
        USERNAME,
        PASSWORD
    )

    await camera.connect()

    print("Connected:", camera)

    start = datetime.now() - timedelta(hours=HOURS_BACK)
    end = datetime.now()


    print(
        f"Searching {start} -> {end}"
    )


    # Search recordings
    events = await camera.get_recordings(
        channel=CHANNEL,
        start_time=start,
        end_time=end
    )


    print(
        f"Found recordings: {len(events)}"
    )


    count = 0


    for event in events:

        # ==========================
        # FILTER AI PERSON EVENTS
        # ==========================

        if not event.ai:
            continue

        if "person" not in [
            x.lower() for x in event.ai
        ]:
            continue


        print(
            "PERSON:",
            event.start_time,
            event.end_time
        )


        filename = (
            f"person_"
            f"{event.start_time.strftime('%Y%m%d_%H%M%S')}"
            ".mp4"
        )


        path = os.path.join(
            SAVE_DIR,
            filename
        )


        if os.path.exists(path):
            print(
                "Already exists:",
                filename
            )
            continue


        print(
            "Downloading:",
            filename
        )


        await camera.download(
            channel=CHANNEL,
            start_time=event.start_time,
            end_time=event.end_time,
            filename=path
        )


        count += 1


    print(
        f"Finished. Downloaded {count} clips."
    )


    await camera.logout()



if __name__ == "__main__":

    asyncio.run(main())