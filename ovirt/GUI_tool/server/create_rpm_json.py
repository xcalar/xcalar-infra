'''
Takes a build directory and filename as input, creates a json file by that filename
which contains data on each RPM installer found within that build directory.

args to script:
 1st arg (required): abs path to dir to start looking in
 2nd arg (required): name of output file for json
 3rd arg (optional): regex to filter collected dirs by

usage:
  python create_rpm_json.py BUILD_DIR OUTPUT_FILE [regex string]

Example 1:
  # entry for each BuildTrunk build (including symlinks)
  python create_rpm_json.py.py /netstore/builds/byJob/BuildTrunk my_json.json

Example 2:
  # only entries for dirs in which have 1.4. in name (i.e., 1.4.* RC builds)
  python create_rpm_json.py /netstore/builds/ReleaseCandidates my_json.json ".*1\.4.*"

Example 3:
  # entries for dirs with 1.4.1 or 2.0 in name
  python create_rpm_json.py /netstore/builds/ReleaseCandidates my_json.json ".*(1\.4\.1|2\.0).*"

(Built for consumption by Ovirt GUIs Flask server)
'''

import os
import re
import json
import sys

'''
Given an absolute path to some base directory, return a hash with a key for each
dir in that base directory which contains RPM installers
(even if those installers are nested).
Value of each key is another hash, with a key for each type of RPM installer
found in that dir (i.e., prod, debug), and key's value as the abs path to that
RPM installer.
An optional regex allows to only return entries for dirs matching the regex

Example 1:
base_dir='/netstore/builds/ReleaseCandidates/'
returns a hash with an entry for every RC build in that folder:
{
    'xcalar-1.4.0-RC20':
        {'prod': <full path to prod RPM installer for that build>,
         'debug': <full path to debug RPM installer for that build>
        },
    ...
}

Example 2:
base_dir='/netstore/builds/ReleaseCandidates/', regex=".*1.4.1.*"
returns a hash with entry only for dirs in base_dir which have 1.4.1 in the name
'''
def installer_data_hash(base_dir, regex=None):
    # get all the directory names in base_dir.
    # this are not the installers themselves and will still need
    # to traverse in them as the dir structure is differently named
    # in each
    if not os.path.isdir(base_dir):
        raise Exception("{} is not a valid directory, or not accessible by this machine".format(base_dir))
    pattern = None
    if regex:
        pattern = re.compile(regex)
    sub_dirs = {}
    for dI in os.listdir(base_dir):
        if os.path.isdir(os.path.join(base_dir, dI)):
            # if pattern supplied match it
            if (not pattern or (pattern and pattern.match(dI))):
                dir_full_path = os.path.join(base_dir, dI)
                build_root = get_build_type_root(dir_full_path)
                if not build_root:
                    next
                else:
                    rpm_installers = get_rpm_installers(build_root)
                    if rpm_installers:
                        sub_dirs[dI] = rpm_installers
    return sub_dirs

'''
return True/False if a list of directories includes names of
directories we commonly use to house installers of a particular type.
'''
def common_build_flavor_directories(dir_list):
    common_flavors = ["prod", "debug"]
    for name in dir_list:
        if name in common_flavors:
            return True
    return False

'''
Given an absolute path to a directory, return the directory within it
where installer directories are housed per build-type (if any).  (Returns
the abs path passed in if the build type dirs begin directly there.)

Example:
/netstore/builds/ReleaseCandidates/xcalar-1.4.1-RC19/

Returns:
/netstore/builds/ReleaseCandidates/xcalar-1.4.1-RC19/20181212-6acf0ca0/

because this is the dir where the dirs containing installers, per build type, begin.
i.e.:
(xcve) jolsen@komogorov:/netstore/builds/ReleaseCandidates/xcalar-1.4.1-RC19/20181212-6acf0ca0$ ls
BUILD_SHA  debug  prod

However, if you passed:
/netstore/builds/byJob/BuildTrunk/2734/
it would return
/netstore/builds/byJob/BuildTrunk/2734/
as the individual build type dirs begin here.

Returns None if no such directory can be identified for the directory requsted.
'''
def get_build_type_root(build_dir_root):
    # start at build_dir_root, get all dirs in it, then traverse downward,
    # until one of the dirs contains the known directories for commo build types
    for root, dirs, files in os.walk(build_dir_root, topdown=True):
        # root is always an abs path, since build_dir_root is an abs path
        if common_build_flavor_directories(dirs):
            return root

'''
Given a directory which contains dirs of installers per build-type (prod, debug, etc.),
return a hash of key/value pairs:
<build type>/<full path to RPM installer for that build type>

Example:
build_dir_root: /netstore/builds/byJob/BuildTrunk/10693
returns:
{'prod': '/netstore/builds/byJob/BuildTrunk/10693/prod/xcalar-2.0.0-2734-installer',
 'debug': '/netstore/builds/byJob/BuildTrunk/10693/debug/xcalar-2.0.0-2734-installer'
}
(because the 'prod' and 'debug' dirs begin directly in that build directory)

but for an RC:
build_dir_root: /netstore/builds/ReleaseCandidates/xcalar-1.4.1-RC19/20181212-6acf0ca0
returns:
{'prod': '/netstore/builds/ReleaseCandidates/xcalar-1.4.1-RC19/20181212-6acf0ca0/xcalar-1.4.1-2527-installer',
 'debug': '/netstore/builds/ReleaseCandidates/xcalar-1.4.1-RC19/20181212-6acf0ca0/xcalar-1.4.1-2527-installer'
}
while:
build_dir_root: build_dir_root: /netstore/builds/ReleaseCandidates/xcalar-1.4.1-RC19
would return {} (since there are no build type dirs located directly there)
'''
def get_rpm_installers(build_dir_root):
    # build_dir_root should be the root of a release. (where 'prod', 'debug', etc. folders live)
    # get the rpm installers within those individual folders.
    rpm_installers = {}
    for dI in os.listdir(build_dir_root):
        base_dir = os.path.join(build_dir_root, dI)
        if os.path.isdir(base_dir):
            # probably a release dir, let's check!
            rpm_installer = get_rpm_installer_from_base(base_dir)
            if rpm_installer:
                rpm_installers[dI] = rpm_installer
    return rpm_installers

'''
Given abs path to a directory, returns abs path to RPM installer found in that directory.
- RPM INSTALLERS ARE IDENTIFIED BASED ON OUR CURRENT NAMING CONVENTIONS ONLY.
- The RPM installer must be directly in that dir; does NOT look in nested dirs.
- Fails on multiple matches.
(For example, build dir /netstore/builds/byJob/BuildTrunk/10693/prod/
 contain multiple installers (RPM installer, GUI installer, node installer, etc.).
if you passed this directory as 'root', it would return the path of the RPM installer
in that dir)
'''
def get_rpm_installer_from_base(root):
    # check for filenames with '-installer' in it
    valid_patterns = [re.compile(".*-installer$"), re.compile(".*-installer-OS.*")]
    found_rpm = []
    for dI in os.listdir(root):
        joined_name = os.path.join(root, dI)
        if os.path.isfile(joined_name):
            # make sure it's not one of the shell scripts
            #fileparts = os.path.splitext(joined_name)
            #if fileparts[len(fileparts)-1] == '.sh':
            #    print("it's a shell script")
            for pattern in valid_patterns:
                if pattern.match(joined_name):
                    found_rpm.append(joined_name)
                    break

    if len(found_rpm) == 1:
        return found_rpm[0]
    elif len(found_rpm) > 1:
        # sometimes you're having more than one RPM Installer;
        # there's a build bug which causes installers from multiple build runs
        # to congregate in a single build directory.
        # sort and take the latest
        found_rpm.sort()
        print("\nWARNING:: HIT BUILD BUG:: Found multiple rpm installers in "
            "build dir {}: {}. Skipping this entry!".format(root, found_rpm))
    return None # didn't find any RPM installers. where are they? :'(


################  START ####################

if len(sys.argv) < 2:
    raise Exception("\n\nPlease supply first arg: directory to gather installer data from for json\n")
if len(sys.argv) < 3:
    raise Exception("\n\nPlease supply second arg: name of json file to output the data to\n")

# sys.argv[0] is name of python script!

# user arg 1 (required) : dir to collect installers from (example: /netstore/builds/ReleaseCandidates"
base_dir = sys.argv[1]
# user arg 2 (required) : output file for json
output_file = sys.argv[2]
# user arg 3 (optional) : regex to filter results by (example: ".*1\.4.*")
regex = None
if len(sys.argv) >= 4:
    regex = sys.argv[3]

if not os.path.isdir(base_dir):
    raise Exception("\n\ndir {} is not accessible, or does not exist.".format(base_dir))
if os.path.isfile(output_file):
    raise Exception("\n\n{} already exists!".format(output_file))

installer_data = installer_data_hash(base_dir=base_dir, regex=regex)
dir_list_json = json.dumps(installer_data)
with open(output_file, 'w') as write_file:
    json.dump(installer_data, write_file, indent=4, sort_keys=True)
