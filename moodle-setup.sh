#!/bin/bash
#--------------------References----------------#
#https://docs.moodle.org/311/en/Installing_Moodle#Download_and_copy_files_into_place

#--------------------/References----------------#


#create debugging function 
dval=0
#debug function should be ran with "FUNCNAME" variable calling the name of given function
debug_function(){
    #toggle hashtag of echo to display or not
    echo "$dval $*"
    #if echo is commented then debug text will not appear
    #if echo is active then text after function name will appear
    ((dval++))
}

#--------------------Variables----------------#
debug_function Variables
OS=$(uname)
current_user=$(whoami)
line="++---------------------------++----------------------------------++"
#change defaults if needed
domain="moodle"
domain_path="/var/www/html/"
moodle_path="${domain_path}/Moodle"
moodle_data="/var/www/moodledata"
user="username_here"
admin_email="user@email.com_here"
# pkgs to install on system
linux_installs="diceware software-properties-common mariadb-server net-tools ufw apache2 mysql-client mysql-server php7.4 libapache2-mod-php graphviz aspell ghostscript clamav php7.4-pspell php7.4-curl php7.4-gd php7.4-intl php7.4-mysql php7.4-xml php7.4-xmlrpc php7.4-ldap php7.4-zip php7.4-soap php7.4-mbstring git"
mac_installs="httpd mysql php diceware"
sql_db_name="${domain//-/}db"
php_files="/Applications/MAMP/conf/php7.4.2/php.ini /Applications/MAMP/bin/php/php7.4.2/conf/php.ini"
#--------------------/Variables----------------#

#--------------------Initial Actions----------------#
debug_function Initial Actions

sudo mkdir -p $moodle_path $domain_path $moodle_data
#--------------------/Initial Actions----------------#


#--------------------Functions----------------#
debug_function Functions Start
#check for existing server. Return apache, nginx, or both
server_check(){
    debug_function "$FUNCNAME"
    #check for OS and output server status
    #check on all server types based on OS and save as variable
    if [ "$OS" == "Darwin" ];then
        #prevent from running on mac if help menu isn't initiated
        #FINISHME nginx_check="$()"
        apache_check="$(httpd -v)"
        
    else
        #check if apache or ngnix are already installed on the server 
        nginx_check="$(dpkg --get-selections | grep nginx)" &> /dev/null
        apache_check="$(dpkg --get-selections | grep apache)" &> /dev/null
        
    fi

    #perform check on all server types based on OS and save as variable
    if [[ -z "$nginx_check" && -z "$apache_check" ]];then
        server="none"
    elif [ -z "$nginx_check" ];then
        server="apache"
    elif [ -z "$apache_check" ];then
        server="nginx"
    else
        #assume both servers are installed
        server="both"
    fi
}


required_installs(){
    if [ "$OS" == "Darwin" ];then
        #assume mac
        #kill any instance of apache
        sudo apacheclt stop &> /dev/null
        sudo launchctl unload -w /Systems/Library/LaunchDaemons/org.apache.httpd.plist &> /dev/null
        
        #install apache using brea (brew must be installed)
        which brew &> /dev/null|| /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        for pkg in $mac_installs;do
            brew install "$pkg"
            echo "$pkg installed"
        done
        #start apache server
        ##FIXME mamp not working, not saving configuration
        sudo brew services start apache2
        sudo /usr/sbin/apachectl start
        mac_moodle_install
        #end mac install
    else
        #assume linux
        #use loop to prevent break from single non usable pkg

        #add php repo
        sudo add-apt-repository ppa:ondrej/php && sudo apt update
        for pkg in $linux_installs;do 
            #install pkg from above , disable stout
            which "$pkg" || sudo apt install -y "$pkg" &> /dev/null
            echo "$pkg installed"
        done
        sudo systemctl restart apache2
        #enable apache to start on reboot
        sudo systemctl enable apache2

        #end Linux install section
    fi
}
linux_install_maria(){
    #path, domain, adminUser, sql_pass all defined in appacheAttribute function
    #security settings
    sudo echo -e "US/Eastern" > /etc/timezone
    dpkg-reconfigure -f noninteractive tzdata
    #detect php version
    php_version=$(php -v |cut -d " " -f 2|cut -d "~" -f 1|head -n 1)
    #define the timezone to the php.ini for security 
    sudo chmod 666 /etc/php/*/apache2/php.ini
    sudo sed -i "s/\;date.timezone =/date.timezone = US\/Eastern/" /etc/php/"${php_version}"/apache2/php.ini
    sudo systemctl enable mariadb.service
    sudo echo -e "processing...."
    #all www traffic on entire server 
    #confirgure here if ports need to be opened for other services
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw allow ssh
    sudo ufw limit ssh
    sudo ufw --force enable
    sudo systemctl start ufw

    ##database creation
    #server hardening script Requires user input
    #sudo mysql_secure_installation
    #-e allows passing of commands , sudo allows running as root user
    #create default sql db
    sudo mariadb -e "CREATE DATABASE $sql_db_name DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
    #essentially create sql user based on the current user
    sudo mariadb -e "GRANT ALL PRIVILEGES ON $sql_db_name.* TO '$current_user'@'localhost' IDENTIFIED BY '$sql_pass';"
    sudo mariadb -e "FLUSH PRIVILEGES;"
}

download_moodle(){
    #download moodle data to moodle path
    cd /opt || exit
    #prevent download if exist
    if [[ ! -e /opt/moodle ]];then
        #assume moodle does not exist and download
        sudo git clone https://github.com/moodle/moodle.git
    else
        #assume it esist and move to next step
        printf "moodle git directory already seems to be installed.\n"
    fi
}
mooodle_install(){
    #instructions taken from https://docs.moodle.org/400/en/Git_for_Administrators
    #install git
    cd /opt/moodle || exit
    git branch -a
    git branch --track MOODLE_400_STABLE origin/MOODLE_400_STABLE
    git checkout MOODLE_400_STABLE
    #install to /var/www/html
    sudo cp -R /opt/moodle $domain_path


    sudo chmod -R 777 $moodle_path
    #run install as www-data or apache
    sudo -u www-data /usr/bin/php $moodle_path/admin/cli/install.php
}
mac_moodle_install(){
    #download moodle dmg file to Downloads
    cd ~/Downloads
    wget https://download.moodle.org/download.php/direct/macosx/Moodle4Mac-311.dmg
    hdiutil mount Moodle4Mac-311.dmg
    sudo cp -R /Volumes/Moodle4Mac-311/MAMP /Applications
    #configure PHP
    configure_php
    #open MAMP
    echo "Opening Moodle Apache MySQL PHP (MAMP) Application"
    open /Applications/MAMP/MAMP.app
    #unmount Moodle dmg
    hdiutil detach /Volumes/Moodle4Mac-311
    sleep 1
    open /Applications/iTerm.app
    echo "Open MAMP settings and \"Set Web & MySQL ports to 80 & 3306\""
    echo "Select \"Start Servers\" in the MAMP Application"
    sleep 7
    open /Applications/MAMP/MAMP.app
}
configure_php(){
    #configure moodle php settings
    #increase post and upload size to 3GB from 8MB
    for file in $php_files;do
        sed "post_max_size|s|8M|3G|g" $file
        sed "upload_max_filesize|s|8M|3G|g" $file
    done
}
setup_apache(){
    #edit config file for fqdn
    echo "$domain localhost" | sudo tee -a /etc/apache2/conf-available/fqdn.conf

    #create sample page
    sudo cp /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-available/$domain.conf  

    sudo sed -i "s|/var/www/html|/var/www/$domain|g" /etc/apache2/sites-available/$domain.conf
    #enable fqdn
    sudo a2enconf fqdn

    #disable defualt site
    #enable domain
    sudo a2dissite 000-default && sudo a2ensite $domain
    sudo a2enmod ssl
    sudo apache2ctl configtest
    sudo systemctl reload apache2
    #restart apache
    sudo /etc/init.d/apache2 restart

    #create sample page
    echo "<b>Hello! $domain is working!</b>" > $moodle_path/index.html
}

fix_permissions(){
    sudo chown -R www-data:www-data $moodle_path
    sudo chmod -R 0755 $moodle_path
    sudo chown -R www-data:www-data $moodle_data
    sudo chmod -R 777 $moodle_data
}

display_information(){
    printf "Script has successfully ran for $domain\n\nThe web portion can be found at:$local_ip/moodle
    The Moodle Files can be found at: $moodle_path\nUsername:$user\nSQL Database Name:$sql_db_name\nSQL Password:$sql_pass
    Finish set up by visiting $local_ip/moodle\n"
}
#--------------------/Functions----------------#

#--------------------/Boiler Plat Import----------------#
### When standard imports are identified they can fit here.
## Import Courses
## Import Questions
## Import Settings
#--------------------/Import----------------#

#--------------------Script Start----------------#
debug_function script start
server_check
required_installs
#diceware and net-tools may be required for install
base_pass=$(diceware -n 5)
admin_pass=$(diceware -n 5)
sql_pass=$(diceware -n 5)
local_ip=$(ifconfig|grep "netmask 255.255.255.0"|cut -d ' ' -f 10)
download_moodle
fix_permissions
mooodle_install
fix_permissions
display_information

#--------------------/Script End----------------#