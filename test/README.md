jenkins.sh is the script that spawns a temporal web server and triggers the test suite
server.py is the web server code:
	`python server.py -t TARGET_HOST` will run using virtual browser (invisible)
	or `python server.py -t TARGET_HOST -v` will run using actual browser (visible)

Environment Setup
-- Ubuntu --
sudo apt-get install -y libnss3-dev chromium-browser
wget http://chromedriver.storage.googleapis.com/2.24/chromedriver_linux64.zip
unzip chromedriver_linux64.zip
chmod +x chromedriver
sudo mv chromedriver /usr/bin/
sudo apt-get install -y libxss1 libappindicator1 libindicator7
sudo apt-get install -y python-pip
sudo pip install pyvirtualdisplay selenium
sudo apt-get install -y Xvfb

-- Centos7 --
< TODO: fix chromium-browser crashes on Centos7 >
sudo yum install -y libnss3.so
sudo rpm -Uvh http://install.linux.ncsu.edu/pub/yum/itecs/public/chromium/7/noarch/chromium-release-2.2-1.noarch.rpm
sudo yum install -y chromium
sudo yum install -y python-virtualenv
sudo virtualenv -p /usr/bin/python3 venv-3.4 --python /usr/bin/python
source venv-3.4/bin/activate
sudo pip install selenium
sudo pip install pyvirtualdisplay
sudo yum install -y Xvfb