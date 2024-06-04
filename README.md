# gtdemo

This demo contains

- fake lightning sensor input
- Apache Kafka (+Connect)
- Kafka Streams demo that determines the district from coordinates (GeoJSON by Land NRW/Kreis Gütersloh (2024))
- ClickHouse
- Apache Superset

## Run

### Bundle

```
chmod +x gtdemo
./gtdemo
```

### With Nix

```
nix run github:teutonet/gtdemo --experimental-features 'nix-command flakes'
```

## Web Interface

http://localhost:5055/
