{
  description = "GT demo";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    kafka = pkgs.apacheKafka;
    connect-clickhouse = pkgs.fetchzip {
      url = "https://github.com/ClickHouse/clickhouse-kafka-connect/releases/download/v1.1.0/clickhouse-kafka-connect-v1.1.0.zip";
      hash = "sha256-pNzj9x2imtHvvd3of7Rm67iQ1aMTWFLPQDfdIIXBqi4=";
    };
    retry = cmd: ''
      i=300
      until ${cmd}
      do
        [[ $((i--)) -gt 0 ]] || exit 1
        sleep 1
      done
    '';
    superset =
      pkgs.runCommand "superset" {buildInputs = [pkgs.makeWrapper];}
      ''
        makeWrapper ${pkgs.callPackage ./superset.nix {}}/bin/superset \
          $out/bin/superset \
          --set-default FLASK_APP superset \
          --set-default SUPERSET_SECRET_KEY notsecret \
          --set-default SUPERSET_CONFIG_PATH ${builtins.toFile "superset-config" ''
          PUBLIC_ROLE_LIKE = "Admin"
          TALISMAN_ENABLED = False
          WTF_CSRF_ENABLED = False
          DASHBOARD_AUTO_REFRESH_INTERVALS = [[5, "5 Sekunden"]]
          LANGUAGES = {"de": {"flag": "de", "name": "German"}}
        ''}

        makeWrapper $out/bin/superset{,-server} --add-flags "run -p 8088"
      '';
    sensor = pkgs.writeShellApplication {
      name = "fake-lightning-sensor";
      runtimeInputs = [(pkgs.python312.withPackages (p: with p; [flask confluent-kafka]))];
      text = ''
        cd ${./fake-lightning-sensor}
        python backend.py
      '';
    };
    streams-district = with pkgs;
      maven.buildMavenPackage {
        pname = "streams-district";
        version = "0";
        src = ./streams-district;
        mvnHash = "sha256-KiG8Za9RjHby3Pb9xPDpSo2jobll1xfx0BR3Qb+y6IY=";
        nativeBuildInputs = [makeWrapper];
        installPhase = ''
          mkdir -p $out/bin $out/share/streams-district
          install -Dm644 target/streams-district-jar-with-dependencies.jar $out/share/streams-district

          makeWrapper ${jre}/bin/java $out/bin/streams-district \
            --add-flags "-jar $out/share/streams-district/streams-district-jar-with-dependencies.jar" \
            --set-default DISTRICTS_GEOJSON \
          ${pkgs.fetchzip {
            url = "https://geoportal.kreis-guetersloh.de/opendata/planen_bauen_kataster/ALKIS_VerwaltungsgrenzenKreisGT_EPSG3857_GEOJSON.zip";
            hash = "sha256-709ZSh4azCuFF/VTg7L5mHzmgcsHQojxGqSK1dhV5Lg=";
            stripRoot=false;
          }}/Gemarkungsgrenzen_KreisGT.geojson
        '';
      };
    deps = with pkgs; [coreutils-full kafka clickhouse curl superset jq sensor kafkactl streams-district];
    connectConfig = pkgs.runCommand "connect-properties" {} ''
      exec > $out
      cat "${kafka}/config/connect-distributed.properties"
      echo key.converter.schemas.enable=false
      echo value.converter.schemas.enable=false
      echo plugin.path=${connect-clickhouse}/lib/
    '';
    pregeneratedSupersetDB = pkgs.runCommand "superset-db" {buildInputs = [superset];} ''
      export SUPERSET_HOME=$out
      superset db upgrade
      superset fab create-admin --{{user,first,last}name,password,email}=admin
      superset init
      superset import-dashboards -p ${./superset-export.zip} -u admin
    '';
    gtdemo = pkgs.writeShellApplication {
      name = "gtdemo";
      runtimeInputs = deps;
      text = ''
        tmp=$(mktemp -d --suffix=-gtdemo)
        cd "$tmp"

        cat ${kafka}/config/kraft/server.properties > kafka.properties
        echo log.dirs="$tmp"/kafka >> kafka.properties

        kafka-storage.sh format --config kafka.properties --cluster-id "$(kafka-storage.sh random-uuid)"

        cleanup () {
          kill -9 -$$
        }
        trap cleanup EXIT

        kafka-server-start.sh kafka.properties &

        cd "$(mktemp -d)"
        clickhouse-server &

        ${retry ''clickhouse-client -q "CREATE DATABASE lightning"''}
        clickhouse-client -q "CREATE TABLE lightning.strike
          (
              timestamp DateTime,
              district String
          )
          ENGINE = MergeTree()
          PRIMARY KEY (district, timestamp)"

        connect-distributed.sh "${connectConfig}" &
        ${retry ''curl -f -X PUT http://localhost:8083/connectors/clickhouse/config -H "Content-Type: application/json" -d @${./connect-clickhouse.json}''}

        export SUPERSET_HOME="$tmp"/superset
        cp --no-preserve=mode -r ${pregeneratedSupersetDB} "$SUPERSET_HOME"
        superset-server &

        ${retry "kafkactl get topics"}
        kafkactl create topic lightning_coords

        streams-district &

        fake-lightning-sensor &

        wait -fn
      '';
    };
  in {
    packages.${system} = {
      inherit gtdemo;
      default = gtdemo;
      superset = superset;
    };
  };
}
