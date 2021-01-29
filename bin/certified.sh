#!/bin/bash
docker run -ti --rm -v xcalar_root_ca:/var/lib/certified -w /var/lib/certified certified bash -l
