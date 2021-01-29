#!/opt/xcalar/bin/python3.6

import os
import sys

from xcalar.external.client import Client
from xcalar.container.target.s3environ import S3EnvironTarget

# Files of interest:
# ~/xcalar/src/misc/sdk_demo/lambda/app.py <-- This is the one
# ~/xcalar/src/bin/tests/pyTestNew/io/test_export.py
# ~/xcalar/src/bin/sdk/xdp/xcalar/external/client.py
# ~/xcalar/src/bin/sdk/xdp/xcalar/external/dataflow.py
# ~/xcalar/src/bin/sdk/xdp/xcalar/external/session.py

# This is currently hard coded because there does not
# appear to be a way to paramterize dataflows.

# These are hardcoded in the workbook/project/dataflow/optimzed/SDK !! Wat!??!
REQ_TARGET = 'S3_bucket'
DATAFLOW_NAME = 'Short_Application'
S3_PATH_TO_PROJECT = '/my-xdp-instamart-workbucket-xnzjk0jhphq9/PROJECT_EXPORT_PATH_param.xlrwb_fixed.tar.gz'

project_name = 'superSerialProject'

USAGE = """
Purpose:
       Uploads and executes an "Optimized SDK App" stored inside of a
    "Project" at this location:

    {project_path}

    The path which this exports to is parameterized. The first argument
    to this script is expected to be a Xcalar S3 path, e.g.,

    /xcfield/my/super/cool/file.csv

Usage:
    {script_name} /bucket/dataflow.tgz /bucket/my/export/key
""".format(script_name=sys.argv[0], project_path=S3_PATH_TO_PROJECT)

# This means skip authenticate.
# Requires script to run locally on node0
client = Client(bypass_proxy=True)


def target_exists(name):
    targets = client.list_data_targets()
    return name in [tt.name for tt in targets]


def create_s3_environ_target(name):
    try:
        client.add_data_target(name, 's3environ', {})
    except Exception as e:
        print(f"Failed to create target: '{name}' with error: {e}")
        raise


def get_project_bytes(path):
    s3target = S3EnvironTarget('my_target', '/')
    return s3target.open(path, 'rb').read()


def upload_project(name, project_bytes):
    try:
        client.upload_workbook(workbook_name=name,
                               workbook_content=project_bytes)
    except Exception as e:
        print(f"Unable to upload project: {e}")
        # Could exist, which might be fine... but
        # ... but I do attempt clean up at the end.
        pass


def fix_s3path(s):
    if s.startswith('s3://'):
        return s[4:]
    return s


def main(s3_import_path, s3_export_path):
    # So, we need to check the list of targets for the target
    # we need and create it if it doesn't exist.

    if not target_exists(REQ_TARGET):
        print(f"Target: '{REQ_TARGET}' does not exist")
        create_s3_environ_target(REQ_TARGET)
        print(f"Successfully created target: '{REQ_TARGET}'")

    # Get workbook/project contents and upload it.
    project_bytes = get_project_bytes(s3_import_path)
    upload_project(project_name, project_bytes)

    project = session = dataflow = None
    try:
        # Get our project
        project = client.get_workbook(project_name)
        print(f"Acquired project: {project}")

        session = project.activate()
        print(f"Acquired session: {session}")

        dataflow_list = project.list_dataflows()
        print(f"List of dataflows: {dataflow_list}")

        dataflow = project.get_dataflow(DATAFLOW_NAME)
        print(f"Acquired dataflow: {dataflow}")

        # Execute dataflow with parameters.
        # Per: src/bin/sdk/xdp/xcalar/external/session.py
        # If query state is error we raise an exception.
        # So, if this doens't raise, we successfully executed.
        params = {"EXPORT_PATH": s3_export_path}
        query_name = session.execute_dataflow(dataflow,
                                              optimized=True,
                                              params=params)
        print(f"Successfully executed query graph: {query_name}")
    except Exception as e:
        print(f"Error: {e}")
    finally:
        # This doesn't matter because the cluster get's nuked, but
        # it is good so that this can be re-run without nuking.
        if dataflow is not None:
            # dataflow_list = project.list_dataflows()
            # print(f"List of dataflows: {dataflow_list}")
            # client.delete_dataflow(dataflow_list[0])
            # print(f"Successfully cleaned up dataflow.")
            # So, for some reason these don't delete. FIXME
            dataflow = None
        if session is not None:
            session.destroy()
            print(f"Succesfully cleaned session.")
        if project is not None:
            project.delete()
            print(f"Succesfully cleaned project.")
        # Should we clean up target?


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(USAGE)
        sys.exit(1)
    s3_import_path = sys.argv[1]
    s3_export_path = sys.argv[2]
    # TODO: maybe validate that arg looks like a valid path
    main(fix_s3path(s3_import_path), fix_s3path(s3_export_path))
    sys.exit(0)
