FROM alpine:latest as builder
MAINTAINER Jason Edwards <jason.edwards@capgemini.com>
WORKDIR /root

#ARG GEOIP_CITY_URL=${'http://geolite.maxmind.com/download/geoip/database/GeoLite2-City.mmdb.gz'}
#ARG GEOIP_COUNTRY_URL=${'http://geolite.maxmind.com/download/geoip/database/GeoLite2-Country.mmdb.gz'}
#ARG GEOIP_MOD_URL=${'https://github.com/leev/ngx_http_geoip2_module/archive/3.3.tar.gz'}
#ARG GEOIP_UPDATE_CLI=${'https://github.com/maxmind/geoipupdate/releases/download/v4.7.1/geoipupdate_4.7.1_linux_amd64.tar.gz'}
#ARG GEOIP_URL=${'https://github.com/maxmind/libmaxminddb/releases/download/1.6.0/libmaxminddb-1.6.0.tar.gz'}
ARG LUAROCKS_URL='http://luarocks.org/releases/luarocks-3.7.0.tar.gz'
ARG OPEN_RESTY_URL='http://openresty.org/download/openresty-1.19.3.1.tar.gz'
ARG NAXSI_URL='https://github.com/nbs-system/naxsi/archive/1.3.tar.gz'
ARG MAXMIND_PATH='/usr/share/GeoIP'

RUN apk add build-base coreutils bash gd-dev linux-headers geoip-dev libxslt-dev git make curl-dev openssl-dev \
    openssl libgcc perl-dev pcre-dev pcre readline-dev tar curl zlib-dev gd geoip libxslt zlib --no-cache
RUN mkdir -p openresty luarocks naxsi geoip geoipupdate \
    ngx_http_geoip2_module $MAXMIND_PATH

# Prepare
RUN curl -ksSL "$OPEN_RESTY_URL" | tar xzv --strip-components 1 -C openresty/
RUN curl -ksSL "$LUAROCKS_URL" | tar xzv --strip-components 1 -C luarocks/
RUN curl -ksSL "$NAXSI_URL" | tar xzv --strip-components 1 -C naxsi/
#RUN curl -ksSL "$GEOIP_URL"        | tar xzv --strip-components 1 -C geoip/
#RUN curl -ksSL "$GEOIP_UPDATE_CLI" | tar xzv --strip-components 1 -C geoipupdate/
#RUN curl -ksSL "$GEOIP_MOD_URL"    | tar xzv --strip-components 1 -C ngx_http_geoip2_module/

#RUN pushd geoip && \
#    ./configure && \
#    make check install && \
#    echo "/usr/local/lib" >> /etc/ld.so.conf.d/libmaxminddb.conf && \
#    curl -fSL ${GEOIP_COUNTRY_URL} | gzip -d > ${MAXMIND_PATH}/GeoLite2-Country.mmdb && \
#    curl -fSL ${GEOIP_CITY_URL} | gzip -d > ${MAXMIND_PATH}/GeoLite2-City.mmdb && \
#    chown -R 1000:1000 ${MAXMIND_PATH} && \
#    popd

# RUN pushd geoipupdate &&\
#     ./configure && \
#     make check install && \
#     popd

#RUN echo "Checking libmaxminddb module" && \
#    ldconfig && ldconfig -p | grep libmaxminddb

#RUN pushd openresty && \
#    ./configure --add-dynamic-module="/root/ngx_http_geoip2_module" \
#                --add-module="../naxsi/naxsi_src" \
#                --with-http_realip_module \
#                --with-http_stub_status_module && \
#    make install && \
#    popd

RUN cd openresty && \
    ./configure --add-module="../naxsi/naxsi_src" \
                --with-http_realip_module \
                --with-http_stub_status_module && \
    make -j4
RUN cd luarocks && \
    ./configure --with-lua=/usr/local/openresty/luajit \
                --lua-suffix=jit-2.1.0-beta2 \
                --with-lua-include=/usr/local/openresty/luajit/include/luajit-2.1 && \
    make -j4 build

RUN mkdir -p /etc/keys && \
    openssl req -x509 -newkey rsa:2048 -keyout /etc/keys/key -out /etc/keys/crt -days 360 -nodes -subj '/CN=test' && \
    openssl dhparam -out /usr/local/openresty/nginx/conf/dhparam.pem 2048

FROM alpine:latest
MAINTAINER Jason Edwards <jason.edwards@capgemini.com>
WORKDIR /root/

RUN apk add bash openssl make wget bind-tools dnsmasq --no-cache && \
    mkdir -p /etc/keys

COPY --from=builder /root/openresty/ /root/openresty/
RUN cd /root/openresty/ && make install

COPY --from=builder /root/luarocks/ /root/luarocks/
RUN cd /root/luarocks/ && make install

COPY --from=builder /etc/keys/ /etc/keys/
COPY --from=builder /usr/local/openresty/nginx/conf/dhparam.pem /usr/local/openresty/nginx/conf/

# Install NAXSI default rules...
RUN mkdir -p /usr/local/openresty/naxsi/
ADD ./naxsi/location.rules /usr/local/openresty/naxsi/location.template
ADD ./nginx*.conf /usr/local/openresty/nginx/conf/
RUN mkdir -p /usr/local/openresty/nginx/conf/locations /usr/local/openresty/nginx/lua
ADD ./lua/* /usr/local/openresty/nginx/lua/
RUN md5sum /usr/local/openresty/nginx/conf/nginx.conf | cut -d' ' -f 1 > /container_default_ngx
ADD ./defaults.sh /
ADD ./go.sh /
ADD ./enable_location.sh /
ADD ./location_template.conf /
ADD ./logging.conf /usr/local/openresty/nginx/conf/
ADD ./security_defaults.conf /usr/local/openresty/nginx/conf/
ADD ./html/ /usr/local/openresty/nginx/html/
ADD ./readyness.sh /
ADD ./helper.sh /
ADD ./refresh_geoip.sh /
RUN luarocks install uuid luasocket
RUN adduser -u 1000 nginx && \
    install -o nginx -g nginx -d \
      /usr/local/openresty/naxsi/locations \
      /usr/local/openresty/nginx/{client_body,fastcgi,proxy,scgi,uwsgi}_temp && \
    chown -R nginx:nginx /usr/local/openresty/nginx/{conf,logs} /usr/share/GeoIP
WORKDIR /usr/local/openresty
EXPOSE 10080 10443
USER 1000
ENTRYPOINT [ "/go.sh" ]
