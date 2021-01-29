Follow the steps below, to get the VMshop GUI running on some host machine.
(VMShop GUI is the tool that was originally running at https://vmshop.int.xcalar.com:1224)

---------------------------------------------------------------

--> (1) Make sure you have a xcalar-infra repo on the machine you wish to host the GUI on.

     (the commands from here on out assume an env variable XLRINFRADIR is pointing to
      that xcalar-infra repo)

--> (2) Set up for Caddy server (make sure to do this before step 3b)

     -- (2a): Copy certs on to host machine, if they are not there already.
              the two files needed are:
                   $XLRINFRADIR/ovirt/GUI_tool/server/vmshop.int.xcalar.com.crt
                   $XLRINFRADIR/ovirt/GUI_tool/server/vmshop.int.xcalar.com.key
               If these files are already present, skip to the next step.
               If these files are not present, you can obtain a copy of them on a tarfile on netstore:

               cp /netstore/users/jolsen/vmshop.int.xcalar.com-certs.tar.gz $XLRINFRADIR/ovirt/GUI_tool/server/
               cd $XLRINFRADIR/ovirt/GUI_tool/server && tar -xvf vmshop.int.xcalar.com-certs.tar.gz


     -- (2b): Modify Caddyfile: $XLRINFRADIR/ovirt/GUI_tool/server/vmshop_caddyfile.conf
              to use the certs from (2a).  You can do this as follows:

            * open $XLRINFRADIR/ovirt/GUI_tool/server/vmshop_caddyfile.conf
            * Scroll to the line that starts with 'tls'.
            * Edit the line so that it has the following content:
              tls <path to your infra repo>/ovirt/GUI_tool/server/vmshop.int.xcalar.com.crt <path to your infra repo>/ovirt/GUI_tool/server/vmshop.int.xcalar.com.key
              NOTE: make sure <path to your infra repo> is the full path to your infra repo; don't use $XLRINFRADIR env variable here

--> (3) Start the servers on the machine that will host the GUI::

      -- (2a) start flask server (starts http Flask server)

          cd $XLRINFRADIR/ovirt/GUI_tool/server && bash -x startServer.sh

      -- (2b) start Caddy server (starts https server that proxies reqeuests to Flask server)

          cd $XLRINFRADIR/ovirt/GUI_tool/frontend && caddy -conf=$XLRINFRADIR/ovirt/GUI_tool/server/vmshop_caddyfile.conf

--> (4) Ensure you have required files::

      -- (4a) Make sure the file 'RCs.json' is present in $XLRINFRADIR/ovirt/GUI_tool/server;
              the flask server will consume this file when building the RCs dropdown menu.
              (The json entries in this file are what get displayed in that dropdown menu.)

              If RCs.json is NOT present in $XLRINFRADIR/ovirt/GUI_tool/server, you can generate
              one as follows:

                cd $XLRINFRADIR/ovirt/GUI_tool/server && python create_rpm_json.py /netstore/builds/ReleaseCandidates RCs.json ".*1\.4.*"

              a couple notes (in case you care):
              * that second arg, RCs.json, specifies what filename to save the output json as;
                the flask server looks for a file by this name so don't just supply any random name when you run the script.
              * that third arg, ".*1\.4.*" is a regex, it specifies to only include json entries
                for builds with 1.4 in the name of the build dir.  You don't have to include this, but if you don't
                that RCs dropdown menu is going to have options for every single RC build dir, including possibly symlinks.
                Is anyone really in need of installing such old RC builds?

--> (5) Finally, verify js server URL matches hostname on machine servers were started on:

       On the machine you've started the servers on,
       Check the file $XLRINFRADIR/ovirt/GUI_tool/frontend/assets/js/ovirtGuiScripts.js ;
       The variable var SERVER_URL should have the hostname of the machine you started
       the caddy server on; this is the URL the GUI will send API requests to.

--> (6) OPTIONAL, and ONLY on Centos7 machine! 

       If you want to set up systemd to start these servers for you automatically
       each time the machine starts up, you can run the following script:

         cd $XLRINFRADIR/ovirt/GUI_tool/install && bash installVmshop.sh

       This script should set up systemd services for both the flask and caddy server
       which you started up manually in steps (2a) and (2b).

-------------------------------------------------------------------

If you have done all the above, you should be able to go to:

https://<hostname>.int.xcalar.com:1224

where <hostname> is the hostname of the machine you have started the servers (1) and (2) on.

At the login prompt, you can log in with your Xcalar LDAP credentials.

------------------------------------------------------------------
