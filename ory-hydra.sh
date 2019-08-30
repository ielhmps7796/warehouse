
function main(){

	`docker network create hydraguide`

	docker run \
	    --network hydraguide \
	    --name ory-hydra-example--postgres \
	    -e POSTGRES_USER=hydra \
	    -e POSTGRES_PASSWORD=secret \
            -e POSTGRES_DB=hydra \
            -d postgres:9.6

	echo "1"

	varp=`cat ./conf | grep secrets_system`
	export SECRETS_SYSTEM=${varp#*=}
	vard=`cat ./conf | grep dsn`
	export DSN=${vard#*=}

        docker run -it --rm --entrypoint hydra oryd/hydra:v1.0.0 help serve

	docker run -it --rm \
	    --network hydraguide \
	    oryd/hydra:v1.0.0 \
	    migrate sql --yes $DSN
	echo "2"

	varip=`cat ./conf | grep ip`
	IP=${varip#*=}

	varcallback=`cat ./conf | grep callback`
	CALLBACK=${varcallback#*=}

	docker run -d \
	    --name ory-hydra-example--hydra \
	    --network hydraguide \
	    -p 9000:4444 \
	    -p 9001:4445 \
	    -e SECRETS_SYSTEM=$SECRETS_SYSTEM \
	    -e DSN=$DSN \
            -e URLS_SELF_ISSUER=https://$IP:9000/ \
            -e URLS_CONSENT=http://$IP:9020/consent \
            -e URLS_LOGIN=http://$IP:9020/login \
	    oryd/hydra:v1.0.0 serve all
         echo "3"

	docker run -d \
	    --name ory-hydra-example--consent \
            -p 9020:3000 \
	    --network hydraguide \
            -e HYDRA_ADMIN_URL=https://ory-hydra-example--hydra:4445 \
	    -e NODE_TLS_REJECT_UNAUTHORIZED=0 \
	    registry.cn-hangzhou.aliyuncs.com/llllllh/ory-hydra-consent-ldap:v0.1

	echo "4"

	docker run --rm -d \
	    -e HYDRA_ADMIN_URL=https://ory-hydra-example--hydra:4445 \
	    --network hydraguide \
            oryd/hydra:v1.0.0 \
            clients create --skip-tls-verify \
	    --id B502BBS \
            --secret 502password \
	    --grant-types authorization_code,refresh_token,client_credentials,implicit \
            --response-types token,code,id_token \
	    --scope openid,offline,photos.read \
            --callbacks https://$CALLBACK:8082/callback
	echo "5"
}
main
