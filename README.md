# moodle setup
 set up moodle learning environment on debian based linux

# Credit
Instructions found on the Moodle website: https://docs.moodle.org/400/en/Step-by-step_Installation_Guide_for_Ubuntu

# Install and Use
**One Liner**
`sudo apt install -y git && git clone https://github.com/k4h4k/moodle-setup && ./moodle-setup/setup.sh`

## After Install
Open your browser and go to http://IP.ADDRESS.OF.SERVER/moodle

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