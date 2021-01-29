#!/bin/bash

build_end=$(curl -s https://jenkins.int.xcalar.com/job/XCETest/lastSuccessfulBuild/buildNumber)
build_start= build_end-100
python ~/xcalar-infra/XceTestAnalyze/app.py -s ${build_start} -e ${build_end}
