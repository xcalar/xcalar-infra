'''
helper functions for the Ovirt server apis
'''

import os
import json

# returns python Obj representation of a json file
def read_json_file(json_filepath):

    if os.path.isfile(json_filepath):
        # check its json file
        if not json_filepath.lower().endswith(('.json')):
            raise Exception("{} is not a json file!".format(json_filepath))
        else:
            with open(json_filepath) as json_file: 
                data = json.load(json_file)
                return data
    else:
        raise Exception("Can't find {}!".format(json_filepath))


