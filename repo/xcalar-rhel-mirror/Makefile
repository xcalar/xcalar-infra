GSBUCKET ?= rhel6-staging.xcalar.net
GSBASE ?= el
RELEASEVER ?= 6Server
REPODIR ?= /srv/reposync/rhel-x86_64-server-6
URL = http://$(GSBUCKET)/$(GSBASE)
VERSION = 1.0
RELEASE = 2
DIST = el6
RHUI = rhui-rhel-server-rhscl-6-rhui-rpms rhui-rhel-6-server-rhui-supplementary-rpms rhui-rhel-6-server-rhui-rpms rhui-rhel-6-server-rhui-rh-common-rpms rhui-rhel-6-server-rhui-optional-rpms
COMPS := $(patsubst %,-g %/comps.xml,$(RHUI))
REPOS := $(patsubst %,-r %, $(RHUI))

.PHONY: all
all: rpm # rhui epel ius

.PHONY: rpm
rpm:
	mkdir -p ~/rpmbuild/SOURCES ~/rpmbuild/SPECS
	git archive --prefix=xcalar-rhel-mirror-$(VERSION)/ HEAD > ~/rpmbuild/SOURCES/xcalar-rhel-mirror-$(VERSION).tar
	sed -e 's,@@URL@@,$(URL),g' -e 's,@@VERSION@@,$(VERSION),g' -e 's,@@RELEASE@@,$(RELEASE),g' xcalar-rhel-mirror.spec.in > ~/rpmbuild/SPECS/xcalar-rhel-mirror.spec
	rpmbuild --define 'dist $(DIST)' -bb ~/rpmbuild/SPECS/xcalar-rhel-mirror.spec

.PHONY: rpm_upload
rpm_upload: rpm
	gsutil cp ~/rpmbuild/RPMS/noarch/xcalar-epel-mirror-$(VERSION)-$(RELEASE).$(DIST).noarch.rpm gs://$(GSBUCKET)/xcalar-epel-mirror.rpm
	gsutil cp ~/rpmbuild/RPMS/noarch/xcalar-ius-mirror-$(VERSION)-$(RELEASE).$(DIST).noarch.rpm gs://$(GSBUCKET)/xcalar-ius-mirror.rpm
	gsutil cp ~/rpmbuild/RPMS/noarch/xcalar-rhel-mirror-$(VERSION)-$(RELEASE).$(DIST).noarch.rpm gs://$(GSBUCKET)/xcalar-rhel-mirror.rpm

.PHONY: rhui
rhui:
	mkdir -p $(REPODIR)/$@
	cd $(REPODIR)/$@ && reposync $(REPOS) -n -d --gpgcheck -l --download_path=`pwd` --downloadcomps --download-metadata
	cd $(REPODIR)/$@ && rm -rf `pwd`/repodata
	cd $(REPODIR)/$@ && createrepo -v $(COMPS) --workers=`nproc` `pwd`

.PHONY: epel
epel:
	mkdir -p $(REPODIR)/$@
	cd $(REPODIR) && reposync -r epel -n -d --gpgcheck -l --download_path=`pwd` --downloadcomps --download-metadata
	cd $(REPODIR)/$@ && rm -rf `pwd`/repodata
	cd $(REPODIR)/$@ && createrepo -v -g comps.xml --workers=`nproc` `pwd`

.PHONY: ius
ius:
	mkdir -p $(REPODIR)/$@
	cd $(REPODIR) && reposync -r ius -n -d --gpgcheck -l --download_path=`pwd` --downloadcomps --download-metadata
	cd $(REPODIR)/$@ && rm -rf `pwd`/repodata
	cd $(REPODIR)/$@ && createrepo -v --workers=`nproc` `pwd`

.PHONY: upload
upload:
	cd $(REPODIR) && gsutil -m rsync -C -d -r `pwd`/ gs://$(GSBUCKET)/$(GSBASE)/$(RELEASEVER)
