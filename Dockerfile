FROM alpine:latest
MAINTAINER Jason Edwards <jason.edwards@capgemini.com>
WORKDIR /root

ARG GEOIP_CITY_AND_COUNTRY_URL='https://github.com/texnikru/GeoLite2-Database/archive/refs/tags/150330.tar.gz'
ARG GEOIP_MOD_URL='https://github.com/leev/ngx_http_geoip2_module/archive/3.3.tar.gz'
ARG GEOIP_UPDATE_CLI='https://github.com/maxmind/geoipupdate/releases/download/v4.7.1/geoipupdate_4.7.1_linux_amd64.tar.gz'
ARG GEOIP_URL='https://github.com/maxmind/libmaxminddb/releases/download/1.6.0/libmaxminddb-1.6.0.tar.gz'
ARG LUAROCKS_URL='http://luarocks.org/releases/luarocks-3.7.0.tar.gz'
ARG OPEN_RESTY_URL='http://openresty.org/download/openresty-1.19.3.1.tar.gz'
ARG NAXSI_URL='https://github.com/nbs-system/naxsi/archive/1.3.tar.gz'
ARG MAXMIND_PATH='/usr/share/GeoIP'
# Install required packages and compile software from source
RUN apk add build-base bash make curl-dev openssl-dev openssl perl-dev pcre-dev pcre readline-dev \
    tar curl wget bind-tools gzip dnsmasq unzip perl-ipc-run3 --no-cache && \
    mkdir -p openresty luarocks naxsi geoip geoipupdate ngx_http_geoip2_module ${MAXMIND_PATH} && \
    curl -ksSL "$OPEN_RESTY_URL" | tar xzv --strip-components 1 -C openresty/ && \
    curl -ksSL "$LUAROCKS_URL" | tar xzv --strip-components 1 -C luarocks/ && \
    curl -ksSL "$NAXSI_URL" | tar xzv --strip-components 1 -C naxsi/ && \
    curl -ksSL "$GEOIP_URL"        | tar xzv --strip-components 1 -C geoip/ && \
    curl -ksSL "$GEOIP_UPDATE_CLI" | tar xzv --strip-components 1 -C geoipupdate/ && \
    curl -ksSL "$GEOIP_MOD_URL"    | tar xzv --strip-components 1 -C ngx_http_geoip2_module/ && \
    cd geoip && \
    ./configure && \
    make -j4 && \
    make -j4 check && \
    make install && \
    mkdir -p /etc/ld.so.conf.d/ && \
    echo "/usr/local/lib" >> /etc/ld.so.conf.d/local.conf && \
    ldconfig / && \
    curl -ksSL ${GEOIP_CITY_AND_COUNTRY_URL} | tar xzv --strip-components 1 -C ${MAXMIND_PATH}/ && \
    chown -R 1000:1000 ${MAXMIND_PATH} && \
    cd /root/geoipupdate && \
    cp geoipupdate /usr/local/bin && \
    cd /root/openresty && \
    ./configure --add-dynamic-module="/root/ngx_http_geoip2_module" \
                --add-module="../naxsi/naxsi_src" \
                --with-http_realip_module \
                --with-http_stub_status_module && \
    make -j4 install && \
    cd /root/luarocks && \
    ./configure --with-lua=/usr/local/openresty/luajit \
                --lua-suffix=jit-2.1.0-beta2 \
                --with-lua-include=/usr/local/openresty/luajit/include/luajit-2.1 && \
    make -j4 build install && \
    mkdir -p /etc/keys /usr/local/openresty/naxsi/ && \
    openssl req -x509 -newkey rsa:2048 -keyout /etc/keys/key -out /etc/keys/crt -days 360 -nodes -subj '/CN=test' && \
    openssl dhparam -out /usr/local/openresty/nginx/conf/dhparam.pem 2048 && \
    mkdir -p /usr/local/openresty/nginx/conf/locations /usr/local/openresty/nginx/lua && \
    md5sum /usr/local/openresty/nginx/conf/nginx.conf | cut -d' ' -f 1 > /container_default_ngx

# Install NAXSI default rules...
COPY ./naxsi/location.rules /usr/local/openresty/naxsi/location.template
COPY ./nginx*.conf /usr/local/openresty/nginx/conf/
COPY ./lua/* /usr/local/openresty/nginx/lua/
COPY ./defaults.sh \
     ./go.sh \
     ./enable_location.sh \
     ./location_template.conf \
     ./readyness.sh \
     ./helper.sh \
     ./refresh_geoip.sh \
     /
COPY ./logging.conf ./security_defaults.conf /usr/local/openresty/nginx/conf/
COPY ./html/ /usr/local/openresty/nginx/html/
RUN luarocks install uuid && luarocks install luasocket && \
    adduser -u 1000 nginx -D && \
    install -o nginx -g nginx -d \
      /usr/local/openresty/naxsi/locations \
      /usr/local/openresty/nginx/{client_body,fastcgi,proxy,scgi,uwsgi}_temp && \
    chown -R nginx:nginx /usr/local/openresty/nginx/conf /usr/local/openresty/nginx/logs \
    /usr/share/GeoIP /etc/keys /usr/local/openresty/nginx && \
    apk del build-base make curl-dev openssl-dev perl-dev pcre-dev readline-dev tar unzip perl-ipc-run3 --no-cache && \
    rm -rf openresty luarocks naxsi geoip ngx_http_geoip2_module
WORKDIR /usr/local/openresty
EXPOSE 10080 10443
USER 1000
ENTRYPOINT [ "/go.sh" ]
