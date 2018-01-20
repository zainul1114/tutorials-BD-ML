#!/usr/bin/env bash
# Time-stamp: <Sat 2018-01-20 18:08 svarrette>
###########################################################################################
# __     __                          _     ____              _       _
# \ \   / /_ _  __ _ _ __ __ _ _ __ | |_  | __ )  ___   ___ | |_ ___| |_ _ __ __ _ _ __
#  \ \ / / _` |/ _` | '__/ _` | '_ \| __| |  _ \ / _ \ / _ \| __/ __| __| '__/ _` | '_ \
#   \ V / (_| | (_| | | | (_| | | | | |_  | |_) | (_) | (_) | |_\__ \ |_| | | (_| | |_) |
#    \_/ \__,_|\__, |_|  \__,_|_| |_|\__| |____/ \___/ \___/ \__|___/\__|_|  \__,_| .__/
#              |___/                                                              |_|
#                  Copyright (c) 2017 UL HPC Team <hpc-sysadmins@uni.lu>
###########################################################################################
# ULHPC (prefered) way to see a Vagrant box configured.
#

SETCOLOR_NORMAL=$(tput sgr0)
SETCOLOR_TITLE=$(tput setaf 6)
SETCOLOR_SUBTITLE=$(tput setaf 14)
SETCOLOR_RED=$(tput setaf 1)
SETCOLOR_BOLD=$(tput setaf 15)

### Local variables
STARTDIR="$(pwd)"
SCRIPTFILENAME=$(basename $0)
SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


MOTD="/etc/motd"
DOTFILES_DIR='/etc/dotfiles.d'
DOTFILES_URL='https://github.com/ULHPC/dotfiles.git'
EXTRA_PACKAGES=

# List of default packages to install
COMMON_DEFAULT_PACKAGES="wget figlet git screen bash-completion rsync vim python-pip htop direnv"

# Easybuild
#export EASYBUILD_MODULES_TOOL=Lmod
export EASYBUILD_MODULE_NAMING_SCHEME=CategorizedModuleNamingScheme
EB_INSTALL_SCRIPT='/tmp/bootstrap_eb.py'
EB_INSTALL_SCRIPT_URL='https://raw.githubusercontent.com/easybuilders/easybuild-framework/develop/easybuild/scripts/bootstrap_eb.py'


######
# Print information in the following form: '[$2] $1' ($2=INFO if not submitted)
# usage: info text [title]
##
info () {
    echo
    echo "${SETCOLOR_BOLD}###${SETCOLOR_NORMAL} ${SETCOLOR_TITLE}${1}${SETCOLOR_NORMAL} ${SETCOLOR_BOLD}###${SETCOLOR_NORMAL}"
}
error() {
    echo
    echo "${SETCOLOR_RED}*** ERROR *** $*${SETCOLOR_NORMAL}"
    exit 1
}

print_usage() {
    cat <<EOF
    $0 [--name "vagrant box name"] \
       [--title "Title"] \
       [--subtitle "Subtitle"] \
       [--desc "description"] \
       [--support "support@mail.com"]
       [-x "pkg1 pkg2 ..."]

Bootstrap a Vagrant box
This will generate the appropriate ${MOTD} file
EOF
}

#######################  Per OS Bootstrapping function ##########################
setup_redhat() {
    info "Running yum update"
    yum update -y  >/dev/null

    info "Installing default packages"
    yum install -y epel-release
    yum install -y ${COMMON_DEFAULT_PACKAGES} bind-utils ${EXTRA_PACKAGES}  >/dev/null

    info "Uninstalling (eventually) existing Puppet installation"
    yum erase -y puppet puppetlabs-release >/dev/null

    info "Adding repo for Puppet 4"
    rpm -ivh https://yum.puppetlabs.com/puppetlabs-release-pc1-el-$1.noarch.rpm

    sleep 1
    info "Installing Puppet and its dependencies"
    yum install -y puppet-agent >/dev/null

    info "installing Environment modules and  LMod"
    yum install -y environment-modules Lmod

    yum groupinstall -y "Development Tools"
    yum install -y openssl-devel libssl-dev libopenssl-devel ncurses-devel libibverbs-dev libibverbs-devel, rdma-core-devel bzip2-devel readline-devel libsqlite3x-devel
}

setup_apt() {
    case $1 in
        3*) codename=cumulus ;;
        6)  codename=squeeze ;;
        7)  codename=wheezy ;;
        8)  codename=jessie  ;;
        9)  codename=stretch  ;;
        12.04) codename=precise ;;
        14.04) codename=trusty  ;;
        16.04) codename=xenial ;;
        *) echo "Release not supported" ;;
    esac

    info "Running apt-get update"
    apt-get update >/dev/null 2>&1

    info "Installing default packages"
    apt-get install -y ${COMMON_DEFAULT_PACKAGES} git-core ${EXTRA_PACKAGES}  >/dev/null

    info "Installing Puppet and its dependencies"
    apt-get install puppet-agent -y >/dev/null
    apt-get install apt-transport-https -y >/dev/null

    info "installing Environment modules and  LMod"
    apt-get install -y environment-modules lmod
    apt-get install -y build-essentials
}

setup_linux() {
    ARCH=$(uname -m | sed 's/x86_//;s/i[3-6]86/32/')
    if [ -f /etc/redhat-release ]; then
        OS=$(cat /etc/redhat-release | cut -d ' ' -f 1)
        majver=$(cat /etc/redhat-release | sed 's/[A-Za-z]*//g' | sed 's/ //g' | cut -d '.' -f 1)
    elif [ -f /etc/SuSE-release ]; then
        OS=sles
        majver=$(cat /etc/SuSE-release | grep VERSION | cut -d '=' -f 2 | tr -d '[:space:]')
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        majver=$VERSION_ID
    elif [ -f /etc/debian_version ]; then
        OS=Debian
        majver=$(cat /etc/debian_version | cut -d '.' -f 1)
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$DISTRIB_ID
        majver=$DISTRIB_RELEASE
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        majver=$VERSION_ID
    else
        OS=$(uname -s)
        majver=$(uname -r)
    fi
    distro=$(echo $OS | tr '[:upper:]' '[:lower:]')
    info "Detected Linux distro: ${distro} version ${majver} on arch ${ARCH}"
    case "$distro" in
        debian|ubuntu) setup_apt $majver ;;
        redhat|fedora|centos|scientific|amazon) setup_redhat $majver ;;
        *) echo "Not supported distro: $distro"; exit 1;;
    esac

}

setup_dotfiles () {
    if [ ! -d "${DOTFILES_DIR}" ]; then
        info "cloning ULHPC/dotfiles repository in '/etc/dotfiles.d"
        git clone ${DOTFILES_URL} ${DOTFILES_DIR}
    fi
    # Correct __git_ps1
    local src_git_prompt="/usr/share/git-core/contrib/completion/git-prompt.sh"
    local dst_git_prompt="/etc/profile.d/git-prompt.sh"
    if [ -f "${src_git_prompt}" ]; then
        info "installing git-prompt to define __git_ps1"
        [ ! -e "${dst_git_prompt}" ] && ln -s ${src_git_prompt} ${dst_git_prompt}
    fi
    local dotfile_install_cmd="${DOTFILES_DIR}/install.sh --offline --force -d ${DOTFILES_DIR} --bash --screen"
    if [ -d "${DOTFILES_DIR}" ]; then
        info "installing dotfiles for 'root' user"
        ${dotfile_install_cmd}
        info "installing dotfiles for 'vagrant' user"
        sudo -u vagrant ${dotfile_install_cmd}
    fi
}

setup_motd() {
    local motd=/etc/motd
    local has_figlet=$(which figlet 2>/dev/null)
    info "setup ${motd}"
    cat <<EOF > ${motd}
================================================================================
 Welcome to the Vagrant box $(hostname)
================================================================================
EOF
    if [ -n "${has_figlet}" ]; then
        cat <<EOF >> ${motd}
$(${has_figlet} -w 80 -c "Virtual $(hostname -s)")
EOF
    fi
    cat <<EOF >> ${motd}
================================================================================
    Hostname.... $(hostname -f)
    OS.......... $(facter os.name) $(facter os.release.full)
    Docs........ Vagrant: http://docs.vagrantup.com/v2/
================================================================================
EOF
}

setup_easybuild() {
    cat <<EOF > /etc/profile.d/easybuild.sh
export EASYBUILD_PREFIX=\$HOME/.local/easybuild
export GLOBAL_EASYBUILD_PREFIX=/opt/apps/
export EASYBUILD_MODULES_TOOL=Lmod
export EASYBUILD_MODULE_NAMING_SCHEME=CategorizedModuleNamingScheme
# Use the below variable to run:
#    module use $LOCAL_MODULES
#    module load tools/EasyBuild
export LOCAL_MODULES=\$EASYBUILD_PREFIX/modules/all
export GLOBAL_MODULES=\$GLOBAL_EASYBUILD_PREFIX/modules/all

alias ma="module avail"
alias ml="module list"
function mu(){
    module use \$GLOBAL_MODULES
    module use \$LOCAL_MODULES
    module load tools/EasyBuild
}

# Prepend directories holding eb file for this turorial to the robot path
# See http://easybuild.readthedocs.io/en/latest/Using_the_EasyBuild_command_line.html?highlight=EASYBUILD_ROBOT#prepending-and-or-appending-to-the-default-robot-search-path

export EASYBUILD_ROBOT_PATHS=\$(find /vagrant/resources/ -name *.eb | xargs dirname | sort | uniq | xargs echo | tr ' ' ':'):

alias global_eb='eb --installpath=\$GLOBAL_EASYBUILD_PREFIX'

EOF
    pip install functools32
    if [ ! -f "${EB_INSTALL_SCRIPT}" ]; then
        curl -o ${EB_INSTALL_SCRIPT} ${EB_INSTALL_SCRIPT_URL}
    fi

    info 'Installing Easybuild'
    sudo -u vagrant EASYBUILD_MODULE_NAMING_SCHEME=CategorizedModuleNamingScheme python ${EB_INSTALL_SCRIPT} ~vagrant/.local/easybuild
}

setup_pyenv() {
    cat <<EOF > /etc/profile.d/pyenv.sh
if [ -d "\$HOME/.pyenv" ]; then
    export PATH="\$HOME/.pyenv/bin:\$PATH"
    eval "\$(pyenv init -)"
    eval "\$(pyenv virtualenv-init -)"
fi
EOF
    if [ ! -h "/home/vagrant/.config/direnv" ]; then
        ln -sf /vagrant/config/direnv /home/vagrant/.config/direnv
    fi
}


######################################################################################
[ $UID -gt 0 ] && error "You must be root to execute this script (current uid: $UID)"


# Parse the command-line options
while [ $# -ge 1 ]; do
    case $1 in
        -h | --help)    print_usage;       exit 0;;
        -V | --version) print_version;     exit 0;;
        -n | --name)      shift; NAME=$1;;
        -t | --title)     shift; TITLE=$1;;
        -st| --subtitle)  shift; SUBTITLE=$1;;
        -d | --desc)      shift; DESC=$1;;
        -s | --support)   shift; SUPPORT_MAIL=$1;;
        -x | --extras)    shift; EXTRA_PACKAGES=$1;;
    esac
    shift
done

# # Let's go
# case "$OSTYPE" in
#     linux*)   setup_linux ;;
#     *)        echo "unknown: $OSTYPE"; exit 1;;
# esac

# [ -f /usr/bin/puppet ] || ln -s /opt/puppetlabs/puppet/bin/puppet /usr/bin/puppet
# [ -f /usr/bin/facter ] || ln -s /opt/puppetlabs/puppet/bin/facter /usr/bin/facter

# setup_dotfiles
# setup_motd
# setup_easybuild

setup_pyenv
