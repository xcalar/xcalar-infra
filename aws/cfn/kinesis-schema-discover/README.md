## Kinesis Schema Discover

A cloudformation template and python script that uses
AWS KinesisAnalytics Service to infer the schema of a
given JSON/CSV on S3.


## Quick start

### Virtual environment
This project has its own isolated Python virtual environment in `.venv`
You must initialize your virtual environment, and then for each shell
you should `source .venv/bin/activate` before running any other commands.
The virtualenv ensures that you're running the correct versions of the
necessary libraries.

    $ make venv
    $ source .venv/bin/activate

Your prompt should change the include the current dir `(kinesis-schema-discover)`.

### Deploy the stack

Pick a unique stack name or it'll default to using the dev stack (`DiscoverSchema-dev`)

    $ export STACK_NAME=DiscoverSchema-abakshi
    $ make deploy

This will deploy the cloudformation template in `template.yaml`. Once done you'll have
a Cloudformation Stack. This stack contains all the various resources such as the lambda
function, IAM permissions, REST Api handlers, etc to allow you to interact with in. If
you make changes to any source file, just run `make deploy` again.

### Source code

The source code is contained in the `discover/` folder _only_. It is in `lambdafn.py` is
the lambda entry point, `discover_kinesis.py` is the Kisnes schema detection library, and
`aws_helper.py` is for general/generic helper functions and classes. You can make changes
to any of these, but when you do run the tests first (see below), then remember to

    $ make deploy

### Tests

You can run the included tests

    $ source .venv/bin/activate
    $ pytest

The tests are stored in `discover/tests/unit/`. If you want to add more tests, please
follow the existing [Pytest](https://docs.pytest.org/en/latest/) conventions

### Clients

Python: A sample python client that discovers the current stack's Lambda REST Api
and calls it is in `client/client.py`

Shell: `client/curl.sh` shows how to call the Lambda function REST Api using curl.



### app.py

app.py uses some of the stack's resources to run the Lambda function locally on
your host's python. If you give it a local file name, it will first upload it
to S3.

    $ python3 app.py localfile.csv s3://xcfield/instantdatamart/tests/readings_200lines.csv

