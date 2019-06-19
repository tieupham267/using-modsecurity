#!/usr/bin/env bash

# Ref: 
# https://blacksaildivision.com/apache-mod-security

# 1. Run as root or with sudo
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root or with sudo."
  exit 1
fi

# 2. Make script exit if a simple command fails and
#    Make script print commands being executed
set -e -x

# 3. Set URLs to the source directories
source_modsec=https://modsecurity.org/download.html
url_download_modsec=https://www.modsecurity.org/tarball/
source_owasp_modsecurity_crs=https://github.com/SpiderLabs/owasp-modsecurity-crs.git

# 4. Look up latest versions of each package
version_modsec=$(curl -sL ${source_modsec} | grep -Eo 'modsecurity\-[0-9.]+[0-9]' | sort -V | tail -n 1)
version_modsec_num=$(curl -sL ${source_modsec} | grep -Eo 'modsecurity\-[0-9.]+[0-9]' | sort -V | tail -n 1 | grep -Eo '[0-9.]+[0-9]')

httpd_apxs=/etc/httpd/bin/apxs
httpd_apr_1_config=/etc/httpd/bin/apr-1-config
httpd_apu_1_config=/etc/httpd/bin/apu-1-config
httpd_modules=/etc/httpd/modules

# Validate
[[ -d $httpd_modules ]] || exit 1
[[ -f $httpd_apxs ]] || exit 1
[[ -f $httpd_apr_1_config ]] || exit 1
[[ -f $httpd_apu_1_config ]] || exit 1

# 4.1 Validate, the var is empty when timeout 
[[ -z "$version_modsec" ]] && exit 1
[[ -z "$version_modsec_num" ]] && exit 1

# 5. Set where OpenSSL and HTTPD will be built
bpath=$(pwd)/modsec-httpd-builder

# 6. Make a "today" variable for use in back-up filenames later
#today=$(date +"%Y-%m-%d")
today=$(date +%F-%H-%M-%S)

# 7. Clean out any files from previous runs of this script
rm -rf \
  "$bpath"

mkdir "$bpath"

if [ ! -d "/etc/httpd/conf/owasp-modsecurity-crs" ]; then
  mkdir "/etc/httpd/conf/owasp-modsecurity-crs"
fi

# 8. Ensure the required software to compile HTTPD is installed
yum update -y -q
yum install -y -q wget vim
yum groupinstall -y -q "Development Tools"
yum install -y -q \
  gcc \
  gettext \
  gcc-c++ \
  zlib-devel \
  pcre-devel \
  libxml2-devel \
  openssl-devel \
  bzip2-devel \
  gdbm-devel \
  libpng-devel \
  libjpeg-devel \
  libXpm-devel \
  libicu-devel \
  libtidy \
  libtidy-devel \
  freetype-devel \
  gmp-devel \
  libtool-ltdl-devel \
  libmhash \
  libmhash-devel \
  libmcrypt \
  libmcrypt-devel \
  expat-devel \
  libnghttp2-devel \
  nss-devel \
  automake \
  libtool 
 
# 9. Download the source files
curl -L "${url_download_modsec}${version_modsec_num}/${version_modsec}.tar.gz" -o "${bpath}/modsecurity.tar.gz"
cd "$bpath"
git clone $source_owasp_modsecurity_crs owasp-modsecurity-crs

# 10. Download the signature files
#curl -L "${source_pcre}${version_pcre}.tar.gz.sig" -o "${bpath}/pcre.tar.gz.sig"
#curl -L "${source_zlib}${version_zlib}.tar.gz.asc" -o "${bpath}/zlib.tar.gz.asc"
#curl -L "${source_openssl}${version_openssl}.tar.gz.asc" -o "${bpath}/openssl.tar.gz.asc"
#curl -L "${source_httpd}${version_httpd}.tar.gz.asc" -o "${bpath}/nginx.tar.gz.asc"
#curl -L "${url_download_modsec}${version_modsec_num}/${version_modsec}.tar.gz" -o "${bpath}/modsecurity.tar.gz.sha256"

# 11. Verify the integrity and authenticity of the source files through their OpenPGP signature
#cd "$bpath"
#GNUPGHOME="$(mktemp -d)"
#export GNUPGHOME
#( gpg --keyserver ipv4.pool.sks-keyservers.net --recv-keys "$opgp_pcre" "$opgp_zlib" "$opgp_openssl" "$opgp_nginx" \
#|| gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$opgp_pcre" "$opgp_zlib" "$opgp_openssl" "$opgp_nginx")
#gpg --batch --verify pcre.tar.gz.sig pcre.tar.gz
#gpg --batch --verify zlib.tar.gz.asc zlib.tar.gz
#gpg --batch --verify openssl.tar.gz.asc openssl.tar.gz
#gpg --batch --verify nginx.tar.gz.asc nginx.tar.gz


# 12. Expand the source files
cd "$bpath"
for archive in ./*.tar.gz; do
  tar xzf "$archive"
done

# 13. Clean up source files
rm -rf \
  "$GNUPGHOME" \
  "$bpath"/*.tar.*



# 20. Build mod_security
#     Ref: https://blacksaildivision.com/apache-mod-security
cd "$bpath"
cd "$version_modsec"

./configure \
  --with-apxs=$httpd_apxs \
  --with-apr=$httpd_apr_1_config \
  --with-apu=$httpd_apu_1_config
make > /dev/null
make install > /dev/null
cp /usr/local/modsecurity/lib/mod_security2.so $httpd_modules

# 21. Create NGINX systemd service file if it does not already exist
#     Ref: https://www.apachelounge.com/viewtopic.php?p=28864
if [ ! -e "/etc/httpd/conf/extra/mod_sec.conf" ]; then
  # Control will enter here if the NGINX service doesn't exist.
  file="/etc/httpd/conf/extra/mod_sec.conf"

  /bin/cat >$file <<'EOF'
LoadModule security2_module modules/mod_security2.so

<IfModule security2_module>
    Include conf/owasp-modsecurity-crs/crs-setup.conf
    Include conf/owasp-modsecurity-crs/rules/*.conf
    
    SecRuleEngine On
    SecRequestBodyAccess On
    SecResponseBodyAccess On 
    SecResponseBodyMimeType text/plain text/html text/xml application/octet-stream
    SecDataDir /tmp
    
    # Debug log
    SecDebugLog /etc/httpd/logs/modsec_debug.log
    SecDebugLogLevel 3
    
    SecAuditEngine RelevantOnly
    SecAuditLogRelevantStatus ^2-5
    SecAuditLogParts ABCIFHZ
    SecAuditLogType Serial
    SecAuditLog /etc/httpd/logs/modsec_audit.log
</IfModule>
EOF
fi

# Add PHP Configure to HTTPD
# vi /etc/httpd/conf/httpd.conf
# Mod Security
#Include conf/extra/mod_sec.conf

# Config
if [ ! -f /etc/httpd/conf/owasp-modsecurity-crs/crs-setup.conf ]; then
  cd "$bpath"
  cd owasp-modsecurity-crs
  cp crs-setup.conf.example /etc/httpd/conf/owasp-modsecurity-crs/crs-setup.conf
fi

cd "$bpath"
cd owasp-modsecurity-crs
cp -rf rules /etc/httpd/conf/owasp-modsecurity-crs/

# Configtest HTTPD
apachectl configtest
apachectl -M