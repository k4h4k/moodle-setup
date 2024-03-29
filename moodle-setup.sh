#!/bin/bash
#--------------------References----------------#
#https://docs.moodle.org/311/en/Installing_Moodle#Download_and_copy_files_into_place

#--------------------/References----------------#


#create debugging function 
dval=0
#debug function should be ran with "FUNCNAME" variable calling the name of given function
debug_function(){
    #toggle hashtag of echo to display or not
    #echo "$dval $*"
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
    debug_function "$FUNCNAME"
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
        echo "Installing Required Packages"
        sudo add-apt-repository -y ppa:ondrej/php &> /dev/null
        sudo apt update &> /dev/null
        for pkg in $linux_installs;do 
            #install pkg from above variable , disable stout
            which "$pkg" || sudo apt install -y "$pkg" &> /dev/null
            echo "$pkg installed"
        done

        sudo systemctl restart apache2
        sudo systemctl restart "$sql_service"
        #enable apache to start on reboot
        sudo systemctl enable apache2
        sudo systemctl enable "$sql_service"

        #end Linux install section
    fi
}
configure_mysql(){
    debug_function "$FUNCNAME"
    #path, hostname, adminUser, sql_pass all defined in appacheAttribute function
    #security settings
    # mkdir -p /var/run/mysqld
    # chown mysql:mysql /var/run/mysqld

    sudo systemctl enable "$sql_service"
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
    #source: https://docs.moodle.org/400/en/Step-by-step_Installation_Guide_for_Ubuntu#Step_2:_Install_Apache.2FMySQL.2FPHP

    # echo "
    # default_storage_engine = innodb
    # innodb_file_per_table = 1
    # innodb_file_format = Barracuda
    # "|sudo tee -a /etc/mysql/my.cnf
    sudo service mysql restart
    systemctl restart "$sql_service"
    
    sudo "$sql_version" -e "CREATE DATABASE $db_name DEFAULT CHARACTER SET $utf_type COLLATE ${utf_type}_unicode_ci;"
    sudo "$sql_version" -e "GRANT ALL PRIVILEGES ON $db_name.* TO $hostname@'localhost' IDENTIFIED BY $sql_pass;"
    sudo "$sql_version" -e "FLUSH PRIVILEGES;"
}
configure_php(){
    debug_function "$FUNCNAME"
    #set php${php_version} as default
    sudo update-alternatives --set php /usr/bin/php${php_version}

    echo -e "US/Eastern" |sudo tee /etc/timezone
    dpkg-reconfigure -f noninteractive tzdata
    
    #define the timezone to the php.ini for security 
    sudo chmod 666 /etc/php/*/apache2/php.ini
    sudo sed -i "s/\;date.timezone =/date.timezone = US\/Eastern/" /etc/php/*/apache2/php.ini
    #sed -i "s/${local_ip}\/moodle/${local_ip}/g" $moodle_path/config.php
    sed -i "/;max_input_var/s/1/5/g" /etc/php/${php_version}/apache2/php.ini
    sed -i "/upload_max_filesize/s/2M/5G/g" /etc/php/${php_version}/apache2/php.ini
    sed -i "/post_max_size/s/8M/5G/g" /etc/php/${php_version}/apache2/php.ini
    #configure moodle php settings
    #increase post and upload size to 3GB from 8MB
    # for file in $php_files;do
    #     sed -i "post_max_size|s|8M|3G|g" "$file"
    #     sed -i "upload_max_filesize|s|8M|3G|g" "$file"
    # done

}
configure_apache(){
    debug_function "$FUNCNAME"
    #required installs
    echo -e "processing...."
    sudo systemctl enable apache2
    source /etc/apache2/envvars
    chmod 666 /etc/apache2/mods-enabled/dir.conf
    echo -e "<IfModule mod_dir.c>
    DirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm
    </IfModule>" |sudo tee -a /etc/apache2/mods-enabled/dir.conf
    sudo systemctl reload apache2
    #create apache configuration files for website including SSL information
    sudo touch /etc/apache2/sites-available/"${hostname}".conf
    sudo chmod 666 /etc/apache2/sites-available/"${hostname}".conf
        echo -e "<VirtualHost *:80>
        ServerName $hostname.lab
        ServerAlias www.$hostname
        ServerAdmin $hostname@localhost
        DocumentRoot $moodle_path
        ErrorLog ${APACHE_LOG_DIR}/error.log
        CustomLog ${APACHE_LOG_DIR}/access.log combined
        </VirtualHost>
        
        " | sudo tee /etc/apache2/sites-available/"${hostname}".conf

        echo -e "<VirtualHost *:80>
        ServerName $hostname.lab
        ServerAlias www.$hostname
        ServerAdmin $hostname@localhost
        DocumentRoot $moodle_path
        ErrorLog ${APACHE_LOG_DIR}/error.log
        CustomLog ${APACHE_LOG_DIR}/access.log combined
        </VirtualHost>"|sudo tee -a /etc/apache2/apache2.conf

    sudo a2ensite "$hostname"
    sudo a2dissite 000-default
    sudo a2enconf fqdn
    sudo chmod 666 /etc/php/*/apache2/php.ini
    #https://quadlayers.com/fix-divi-builder-timeout-error/
    sudo sed -i "/^memory_limit/s/128M/256M/g" /etc/php/${php_version}/apache2/php.ini
    sudo sed -i "/^upload_max_filesize/s/2M/128M/g" /etc/php/${php_version}/apache2/php.ini
    sudo sed -i "/^max_file_uploads/s/20/45/g" /etc/php/${php_version}/apache2/php.ini
    #https://www.wpbeginner.com/wp-tutorials/how-to-fix-the-link-you-followed-has-expired-error-in-wordpress/
    sudo sed -i "/^max_execution_time/s/30/300/g" /etc/php/${php_version}/apache2/php.ini
    sudo sed -i "/^post_max_size/s/8M/128M/g" /etc/php/${php_version}/apache2/php.ini
    sudo sed -i "/^;max_input_vars/s/;//g" /etc/php/${php_version}/apache2/php.ini
    #Create .htaccess file to set new upload size to 10GB
    echo "
    php_value upload_max_filesize 10737418240
    php_value post_max_size 10737418240
    php_value max_execution_time 600
    " | sudo tee "$moodle_path"/.htaccess
    #configure apache.conf to allow override .httaccess
    sudo sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
    sudo apache2ctl configtest && sudo systemctl reload apache2
}
download_moodle(){
    debug_function "$FUNCNAME"
    #download moodle data to moodle path
    cd /opt || exit
    #prevent download if exist
    if [[ ! -e /opt/moodle ]];then
        #assume moodle does not exist and download
        ## source for syntax https://www.freecodecamp.org/news/git-clone-branch-how-to-clone-a-specific-branch/
        git clone --branch MOODLE_400_STABLE https://github.com/moodle/moodle.git
        cd /opt/moodle || exit
    else
        #assume it esist and move to next step
        printf "moodle git directory already seems to be installed.\n Updating\n"
        cd /opt/moodle
        git pull .
    fi
    #install git
    cd /opt/moodle || exit
    
    #copy contents to /var/www/html
    sudo cp -R /opt/moodle/* "$moodle_path"
}
mooodle_install(){
    debug_function "$FUNCNAME"
    #instructions taken from https://docs.moodle.org/400/en/Git_for_Administrators
    #run install as www-data or apache to generate config.php
    sudo -u www-data /usr/bin/php /var/www/moodle/admin/cli/install.php --agree-license --non-interactive --allow-unstable --lang="en" --adminuser="admin" --adminpass="$admin_pass" --adminemail="$hostname@example.com" --wwwroot="http://$local_ip" --dbtype="$sql_version_db_type" --dataroot="$moodle_data" --dbname="$db_name"  --dbuser="$hostname" --dbpass="$sql_pass" --fullname="$hostname" --shortname="$hostname"
    #assume config.php is created
    sudo -u www-data /usr/bin/php /var/www/moodle/admin/cli/install_database.php --agree-license --lang="en" --adminuser="admin"  --adminpass="$admin_pass" --adminemail="$hostname@example.com"
    sudo chmod -R 777 "$moodle_path"
    
}
mac_moodle_install(){
    debug_function "$FUNCNAME"
    #download moodle dmg file to Downloads
    cd ~/Downloads || exit
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


fix_permissions(){
    debug_function "$FUNCNAME"
    sudo chown -R www-data:www-data "$moodle_path" /var/www
    sudo chmod -R 0755 "$moodle_path"
    sudo chown -R www-data:www-data "$moodle_data" "$moodle_data/Imports" "$moodle_data/Imports/*"
    sudo chmod -R 777 "$moodle_data" "$moodle_data/Imports"
    #source:https://docs.moodle.org/400/en/Security_recommendations
    echo -e "Starting  Permission Config for : Directories"
    sudo find "$moodle_path" -type d -exec chmod 755 {} \;
    echo -e "Starting  Permission Config for : Files"
    sudo find "$moodle_path" -type f -exec chmod 644 {} \;
}

set_up_cron(){
    debug_function "$FUNCNAME"
    #source https://docs.moodle.org/400/en/Cron
    echo -e "$(sudo crontab -u root -l)\n* * * * * /usr/bin/php $moodle_path/admin/cli/cron.php" | sudo crontab -u www-data -
    sudo -u www-data /usr/bin/php "$moodle_path"/admin/cli/cron.php --enable
}
restore_backup(){
    debug_function "$FUNCNAME"
    sudo -u www-data /usr/bin/php "$moodle_path"/admin/cli/restore_backup.php --file="$backup_path" --categoryid=1
}
display_information(){
    debug_function "$FUNCNAME"
    echo "
    Finish set up by visiting http://${local_ip}
    SQL Database Name: $db_name - SQL USER: $hostname
    SQL Password: $sql_pass
    $line
    Follow the prompts:
    $line
    Database Type
    Choose: "$sql_version"
    
    Database Settings
    Host server: localhost
    Database: $db_name
    User: $hostname 
    Password: $sql_pass 
    $line
    Environment Checks

    This will indicate if any elements required to run moodle haven't been installed.
    Next next next...

    follow prompts and confirm installation
    Create a Site Administrator Account

    Create your moodle user account which will have site administrator permissions.

    The password you select has to meet certain security requirements. 
    $line
    
    SQL Database Name: $db_name - SQL USER: $hostname
    SQL Password: $sql_pass
    $line
    Moodle Admin: Admin
    Admin Password: $admin_pass

    Finish set up by visiting http://${local_ip}
    "
}
#--------------------/Functions----------------#
user_prompts(){
    debug_function "$FUNCNAME"
    read -p "Hostname Name: " hostname
    #check if hostname is not defined or if blank space is assigned
    if [[ -z "${hostname+x}"||"$hostname" == ""||"$hostname" == "\n" ]];then
        #if nothing detected set to moodle
        hostname="moodle"
        echo "The default hostaname name is $hostname"
    fi
    #remove spaces from hostname    
    hostname=$(echo $hostname|sed 's/ //g')
    db_name="${hostname}db"
    echo "Hostname is: $hostname"
    echo "Database Name is: $db_name"


    printf "SQL Password (won't show when typing) (leave blank to autogenerate): "
    read -s sql_pass
    if [[ -z "${sql_pass+x}"||"$sql_pass" == ""||"$sql_pass" == "\n" ]];then
        #assume user didn't enter a password
        sudo apt install -y diceware &> /dev/null
        sql_pass=$(diceware -n 5)
        printf "\nThe generated password is: $sql_pass\n"
        sleep 2
    else
        #new line
        echo 
    fi

    ## Admin Password
    printf "Admin Password (won't show when typing) (leave blank to autogenerate): "
    read -s admin_pass
    if [[ -z "${admin_pass+x}"||"$admin_pass" == ""||"$admin_pass" == "\n" ]];then
        #assume user didn't enter a password
        sudo apt install -y diceware &> /dev/null
        admin_pass=$(diceware -n 5)
        printf "\nThe generated password is: $admin_pass\n"
        sleep 2
    else
        #new line
        echo 
    fi

}
#--------------------Variables----------------#
debug_function Variables
OS=$(uname)
current_user=$(whoami)
php_version="7.4"
## SQL Type and Vars
#options for sqldb
# sql_version="mysql"
# sql_version_db_type="mysqli"
# sql_service="mysqld"
sql_version="mariadb"
sql_version_db_type="mariadb"
sql_service="mariadb.service"
utf_type="utf8" #or utf8mb4
line="++---------------------------++----------------------------------++"
#change defaults if needed
moodle_path="/var/www/moodle"
moodle_data="/var/www/moodledata"
quarantine_dir="/var/quarantine"
# pkgs to install on system 
linux_installs="apache2 apache2-utils apache2-doc libmysqlclient-dev libexpat1 ssl-cert diceware net-tools poppler-utils ufw mysql-client mysql-server mariadb-server fail2ban php${php_version} php${php_version}-common libapache2-mod-php graphviz aspell ghostscript clamav php${php_version}-pspell php${php_version}-cli php${php_version}-curl php${php_version}-gd php${php_version}-intl php${php_version}-mysql php${php_version}-xml php${php_version}-xmlrpc php${php_version}-ldap php${php_version}-zip php${php_version}-soap php${php_version}-mbstring git"
mac_installs="httpd mariadb-server php diceware"
php_files="/Applications/MAMP/conf/php.2/php.ini /Applications/MAMP/bin/php/php.2/conf/php.ini"
#--------------------/Variables----------------#
create_defualts(){
    debug_function "$FUNCNAME"
    #source:https://docs.moodle.org/dev/Local_plugins#Customised_site_defaults
    echo "
    <?php
    $defaults['moodle']['forcelogin'] = 1;  // new default for $CFG->forcelogin
    $defaults['scorm']['maxgrade'] = 20;    // default for get_config('scorm', 'maxgrade')
    $defaults['moodlecourse']['numsections'] = 11;
    $defaults['moodle']['hiddenuserfields'] = array('city', 'country');
    "|sudo tee "$moodle_path"/local/defaults.php
}
reset_user(){
    #function used to reset user accounts using the php file provided by moodle
    debug_function "$FUNCNAME"
    #source:https://github.com/moodle/moodle/blob/master/admin/cli/reset_password.php
    sudo -u www-data /usr/bin/php "$moodle_path"/admin/cli/reset_password.php --ignore-password-policy --username="$username" --password="$newpassword"
}
set_up_system(){
    debug_function "$FUNCNAME"
    #--------------------Initial Actions----------------#
    debug_function Initial Actions

    sudo mkdir -p $moodle_path $moodle_path $moodle_data $quarantine_dir "$moodle_data/Imports"
    sudo chown -R www-data:www-data $moodle_path $moodle_path $moodle_data $quarantine_dir
    
    sudo apt install -y software-properties-common &> /dev/null && sudo apt update
    #--------------------/Initial Actions----------------#
    #--------------------Script Start----------------#
    debug_function script start
    server_check
    required_installs
    local_ip=$(ifconfig|grep "netmask 255.255.255.0"|cut -d ' ' -f 10)
    download_moodle
    fix_permissions
    #has to be after the install
    configure_php
    configure_mysql
    configure_apache
    fix_permissions
    set_up_cron
    mooodle_install
    display_information

    #--------------------/Script End----------------#
}
linux_update(){
    debug_function "$FUNCNAME"
    sudo apt update --fix-missing && sudo apt -y upgrade
    git pull #assume script is ran from moodle set up dir
    cd $moodle_path && git pull
    pip3 list --outdated --format=freeze | grep -v '^\-e' | cut -d = -f 1 | xargs -n1 pip3 install -U
}
macOS_update(){
    debug_function "$FUNCNAME"
    brew update
    brew upgrade
    brew upgrade --greedy
    brew autoremove
    brew cleanup -s
    rm -rf "$(brew --cache)"
    brew doctor
    brew missing
    sudo periodic daily weekly monthly
    pip3 list --outdated --format=freeze | grep -v '^\-e' | cut -d = -f 1 | xargs -n1 sudo -H python3 -m pip install -U
    softwareupdate -ia
}
### Menu and Run Script ###
#install sudo for systems without default sudo running root
apt install -y sudo &> /dev/null

debug_function Menu Start
PS3='Please enter your choice: '
options=("Set Up Moodle" "Set Up PHP" "Set Up SQL" "Set Up Apache" "Upgrade System" "Fix Permissions" "Reset User Password" "Restore Backup" "Quit")
select opt in "${options[@]}"
do
    case $opt in
        "Set Up Moodle")
            user_prompts
            set_up_system
            #FIXME:create_defualts
            ;;
        "Download Requirments")
            download_moodle
            required_installs
            ;;
        "Set Up SQL")
            user_prompts
            configure_mysql
            ;;
        "Set Up Apache")
            user_prompts
            configure_apache
            ;;
        "Upgrade System")
            linux_update
            ;;
        "Fix Permissions")
            fix_permissions
            ;;
        "Reset User Password")
            user_prompts
            reset_user
            ;;
        "Restore Backup")
            # if [ -z "${1+x}" ];then
            #     #assume no file was passed
            ##FIXME: showing as "file not found"
                echo "This file should be placed in /var/www/"
                read -p "Absolute path to backup (/var/www/backup-moodle2-course-4-courseName-date-num.mbz): " backup_path
            # else
            #     #assume arg is the file to restore
            #     backup_path="$1"
            # fi
            restore_backup
            ;;
        "Quit")
            break
            ;;
        *) echo "invalid option $REPLY";;
    esac
done