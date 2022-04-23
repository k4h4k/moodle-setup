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
linux_sql_function(){
    #path, domain, adminUser, sql_pass all defined in appacheAttribute function
    #security settings
    mkdir -p /var/run/mysqld
    chown mysql:mysql /var/run/mysqld

    sudo systemctl enable mysql.service
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
    sudo mysql -u root mysql<<EOF
CREATE DATABASE $sql_db_name DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;
CREATE USER '$user'@'localhost' IDENTIFIED BY '$sql_pass';
GRANT ALL PRIVILEGES ON $sql_db_name.* TO '$user'@'localhost' IDENTIFIED BY '$sql_pass'
FLUSH PRIVILEGES;
\q
EOF
}
configure_php(){
    sudo echo -e "US/Eastern" > /etc/timezone
    dpkg-reconfigure -f noninteractive tzdata
    #detect php version
    php_version=7.4
    #define the timezone to the php.ini for security 
    sudo chmod 666 /etc/php/*/apache2/php.ini
    sudo sed -i "s/\;date.timezone =/date.timezone = US\/Eastern/" /etc/php/*/apache2/php.ini
    
    sudo sed -i "s|http://${local_ip}/moodle|http://${local_ip}|g" $moodle_path/config.php
    #source https://docs.moodle.org/400/en/Configuration_file
    cp $moodle_path/config-dist.php $moodle_path/config.php

    ##FIXME: Need to update these values in the $moodle_path/config.php
    sed -i "/\$CFG->dbname/s/moodle/$sql_db_name/" config-dist.php
    sed -i "/\$CFG->dbuser/s/username/$user/" config-dist.php
    sed -i "/\$CFG->dbpass/s/password/$sql_pass/" config-dist.php
    sed -i "/\$CFG->wwwroot/s/example.com\/moodle|$local_ip|" config-dist.php
    sed -i "/\$CFG->dataroot/s/\/home\/example\/moodledata|$moodle_data|" config-dist.php

    #configure moodle php settings
    #increase post and upload size to 3GB from 8MB
    for file in $php_files;do
        sed -i "post_max_size|s|8M|3G|g" $file
        sed -i "upload_max_filesize|s|8M|3G|g" $file
    done

}
apache_install_function(){
    debug_function "$FUNCNAME"
    #required installs
    echo -e "processing...."
    echo -e "installing apache2 libapache2-mod-php "
    sudo apt install apache2 libapache2-mod-php -y &> /dev/null
    sudo ufw allow in "WWW Full"
    sudo systemctl enable apache2
    source /etc/apache2/envvars
    chmod 666 /etc/apache2/mods-enabled/dir.conf
    echo -e "<IfModule mod_dir.c>
    DirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm
    </IfModule>" |sudo tee -a /etc/apache2/mods-enabled/dir.conf
    sudo systemctl reload apache2
    #create apache configuration files for website including SSL information
    sudo touch /etc/apache2/sites-available/"${domain}".conf
    sudo chmod 666 /etc/apache2/sites-available/"${domain}".conf
        echo -e "<VirtualHost *:80>
        ServerName $domain
        ServerAlias www.$domain
        ServerAdmin $domain@localhost
        DocumentRoot $moodle_path
        ErrorLog ${APACHE_LOG_DIR}/error.log
        CustomLog ${APACHE_LOG_DIR}/access.log combined
        </VirtualHost>
        
        " | sudo tee /etc/apache2/sites-available/"${domain}".conf

        echo -e "<VirtualHost *:80>
        ServerName $domain
        ServerAlias www.$domain
        ServerAdmin $domain@localhost
        DocumentRoot $moodle_path
        ErrorLog ${APACHE_LOG_DIR}/error.log
        CustomLog ${APACHE_LOG_DIR}/access.log combined
        </VirtualHost>"|sudo tee -a /etc/apache2/apache2.conf

    sudo a2ensite "$domain"
    sudo a2dissite 000-default
    sudo a2enconf fqdn
    sudo chmod 666 /etc/php/*/apache2/php.ini
    #https://quadlayers.com/fix-divi-builder-timeout-error/
    sudo sed -i "/^memory_limit/s/128M/256M/g" /etc/php/7.3/apache2/php.ini && sudo sed -i "/^upload_max_filesize/s/2M/128M/g" /etc/php/7.3/apache2/php.ini && sudo sed -i "/^max_file_uploads/s/20/45/g" /etc/php/7.3/apache2/php.ini
    #https://www.wpbeginner.com/wp-tutorials/how-to-fix-the-link-you-followed-has-expired-error-in-wordpress/
    sudo sed -i "/^max_execution_time/s/30/300/g" /etc/php/7.3/apache2/php.ini && sudo sed -i "/^post_max_size/s/8M/128M/g" /etc/php/7.3/apache2/php.ini&& sudo sed -i "/^;max_input_vars/s/;//g" /etc/php/7.3/apache2/php.ini

    sudo apache2ctl configtest && sudo systemctl reload apache2
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
    sudo git branch -a
    sudo git branch --track MOODLE_400_STABLE origin/MOODLE_400_STABLE
    sudo git checkout MOODLE_400_STABLE
    #install to /var/www/html
    sudo cp -R /opt/moodle/* $moodle_path


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
# setup_apache(){
#     #edit config file for fqdn
#     echo "$domain localhost" | sudo tee -a /etc/apache2/conf-available/fqdn.conf

#     #create sample page
#     sudo cp /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-available/$domain.conf  

#     sudo sed -i "s|/var/www/html|$moodle_path|g" /etc/apache2/sites-available/$domain.conf
#     #enable fqdn
#     sudo a2enconf fqdn

#     #disable defualt site
#     #enable domain
#     sudo a2dissite 000-default && sudo a2ensite $domain
#     sudo a2enmod ssl
#     sudo apache2ctl configtest
#     sudo systemctl reload apache2
#     #restart apache
#     sudo /etc/init.d/apache2 restart

#     #create sample page
#     echo "<b>Hello! $domain is working!</b>" > $moodle_path/index.html
# }


fix_permissions(){
    sudo chown -R www-data:www-data $moodle_path /var/www
    sudo chmod -R 0755 $moodle_path
    sudo chown -R www-data:www-data $moodle_data
    sudo chmod -R 777 $moodle_data
}

set_up_cron(){
    #source https://docs.moodle.org/400/en/Cron
    echo -e "$(sudo crontab -u root -l)\n* * * * * /usr/bin/php $moodle_path/admin/cli/cron.php" | sudo crontab -u root -
}

display_information(){
    echo "
    Finish set up by visiting http://${local_ip}/moodle
    SQL Database Name: $sql_db_name - SQL USER: $user
    SQL Password: $sql_pass

    Follow the prompts:
    Change the path for moodledata

    /var/moodledata
    Database Type

    Choose: mysqli
    Database Settings

    Host server: localhost

    Database: moodle

    User: moodledude (the user you created when setting up the database)

    Password: passwordformoodledude (the password for the user you created)

    Tables Prefix: mdl_
    Environment Checks

    This will indicate if any elements required to run moodle haven't been installed.
    Next next next...

    follow prompts and confirm installation
    Create a Site Administrator Account

    Create your moodle user account which will have site administrator permissions.

    The password you select has to meet certain security requirements. 
    
    Finish set up by visiting http://${local_ip}/moodle
    SQL Database Name: $sql_db_name - SQL USER: $user
    SQL Password: $sql_pass
    "
}
#--------------------/Functions----------------#

#--------------------/Boiler Plat Import----------------#
### When standard imports are identified they can fit here.
## Import Courses
## Import Questions
## Import Settings
#--------------------/Import----------------#
#--------------------Variables----------------#
debug_function Variables

user="username_here"
admin_email="user@email.com_here"


OS=$(uname)
current_user=$(whoami)
line="++---------------------------++----------------------------------++"
#change defaults if needed
domain="moodle"
moodle_path="/var/www/moodle"
moodle_data="/var/www/moodledata"
quarantine_dir="/var/quarantine"
# pkgs to install on system
linux_installs="diceware net-tools ufw apache2 mysql-client mysql-server php php-common libapache2-mod-php graphviz aspell ghostscript clamav php-pspell php-cli php-curl php-gd php-intl php-mysql php-xml php-xmlrpc php-ldap php-zip php-soap php-mbstring git"
mac_installs="httpd mysql php diceware"
sql_db_name="${domain//_/}db"
php_files="/Applications/MAMP/conf/php.2/php.ini /Applications/MAMP/bin/php/php.2/conf/php.ini"
#--------------------/Variables----------------#

#--------------------Initial Actions----------------#
debug_function Initial Actions

sudo mkdir -p $moodle_path $moodle_path $moodle_data $quarantine_dir
sudo chown -R www-data:www-data $moodle_path $moodle_path $moodle_data $quarantine_dir
sudo apt install -y software-properties-common && sudo apt update
#--------------------/Initial Actions----------------#
#--------------------Script Start----------------#
debug_function script start
server_check
#remove instances of php before installs
sudo apt-get --purge remove php-common
required_installs
#diceware and net-tools may be required for install
base_pass=$(diceware -n 5)
admin_pass=$(diceware -n 5)
sql_pass=$(diceware -n 5)
local_ip=$(ifconfig|grep "netmask 255.255.255.0"|cut -d ' ' -f 10)
download_moodle
fix_permissions
apache_install_function
linux_sql_function
mooodle_install
fix_permissions
configure_php
set_up_cron
display_information

#--------------------/Script End----------------#