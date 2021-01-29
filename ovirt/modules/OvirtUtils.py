import os
import subprocess
import sys

# bash lib with functions used by this python script
# it is in <infra>/bin
# will be calling that shell script directly;
# make sure <infra>/bin is in system path of machine running this file, else will not work
INFRA_HELPER_SCRIPT='infra-sh-lib'
# chars that are disallowed in VM names (due to our internal constraints)
ILLEGAL_VMNAME_CHARS = ['.', '_']
# for param validation:
# protected search keywords in Ovirt GUI to disallow as VM names
# (vms_service.list api will fail if one of these words is supplied as the identifier,
# potentially mangling any automated search features if vms can have these names; so don't allow)
PROTECTED_KEYWORDS = ['cluster', 'host', 'fdqn', 'name']

'''
Checks if url can be curled.
Throws ValueError if it can't, else returns True
'''
def _try_curl(url):
    '''
    calls 'check_url' func in bash helper lib, <INFRA>/bin/infra-sh-lib
    will check if url can be curled without downloading.
    you must source the file to call it directly
    '''
    bash_cmd = "bash -c 'source {}; check_url {}'".format(INFRA_HELPER_SCRIPT, url)
    print(bash_cmd)
    try:
        subprocess.check_call(bash_cmd, shell=True)
        return True
    except subprocess.CalledProcessError as e:
        # TODO: customize error based on return code?
        # return_code = e.returncode
        raise ValueError("Can't access this path")

def _is_gui_or_user_installer(installer_url):
    # make sure they have given the regular RPM installer, not userinstaller
    filename = os.path.basename(installer_url)
    if 'gui' in filename or 'userinstaller' in filename:
        return True
    else:
        return False

'''
Validation of VM params

call these functions with a prospective VM param;
if there's an issue a ValueError Exception will be raised
with a message indicating the nature of the error
'''

def validate_hostname(hostname):

    # these are the non-alphanumeric chars which Ovirt allows in vm names
    ovirt_allowed_vmname_chars = ['_', '-']
    # now do a difference on our disallowed chars to find what we're left with
    final_allowed_vmname_chars = set(ovirt_allowed_vmname_chars) - set(ILLEGAL_VMNAME_CHARS)

    # validate all chars in hostanme are legal
    if (any(filter(str.isupper, hostname)) or
        not all(s.isalnum() or s in final_allowed_vmname_chars for s in hostname)):
        raise ValueError("VM basenames may only contain "
            "lower case letters, numbers, "
            "or the chars: {}\n".format(" ".join(final_allowed_vmname_chars)))

    '''
    if the basename begins with one of Ovirt's search refining keywords
    (a string you can type in the GUI's search field to refine a search, ex. 'cluster', 'host')
    then the vms_service.list api will not work.
    this leads to confusing results which are not immediately obvious what's going on
    ensure prospective hostname does not begin with any of these words
    '''
    for ovirtSearchFilter in PROTECTED_KEYWORDS:
        if hostname.startswith(ovirtSearchFilter):
            raise ValueError("VM's basename can not begin with "
                "any of the values: {} (These are protected keywords "
                "in Ovirt)".format(PROTECTED_KEYWORDS))

    # hostname can't begin with a number
    if hostname[0].isdigit():
        raise ValueError("VM basename can not begin with a number")

'''
ensure URL can be curl'd on the local machine,
and doesn't appear as gui or userinstaller
'''
def validate_installer_url(installer_url):

    # attempt to detect if they've not supplied an RPM installer
    if _is_gui_or_user_installer(installer_url):
        raise ValueError("RPM installer required; this looks like a "
            "gui installer or userinstaller")

    # make sure can curl.  Throws value error if curl encounters
    # a problem so let the error bubble up with its error messgae
    _try_curl(installer_url)
