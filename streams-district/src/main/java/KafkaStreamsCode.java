import lombok.AllArgsConstructor;
import lombok.NoArgsConstructor;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.KafkaStreams;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.StreamsConfig;
import org.apache.kafka.streams.kstream.Consumed;
import org.apache.kafka.streams.kstream.Produced;
import org.springframework.kafka.support.serializer.JsonSerde;

import java.util.Date;
import java.util.Properties;

public class KafkaStreamsCode {

    public static class LatLng {
        public Date timestamp;
        public Double lat;
        public Double lng;
    }

    @NoArgsConstructor
    @AllArgsConstructor
    public static class TimestampDistrict {
        public Date timestamp;
        public String district;
    }

    public static void main(String[] args) throws InterruptedException {
        Properties props = new Properties();
        props.put(StreamsConfig.APPLICATION_ID_CONFIG, "streams-district");
        props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, "localhost:9092");

        StreamsBuilder builder = new StreamsBuilder();

        builder.stream("lightning_coords", Consumed.with(Serdes.String(), new JsonSerde<>(LatLng.class)))
                .flatMapValues((String key, LatLng latLng) ->
                        DetermineDistrict.determineDistricts(latLng.lat, latLng.lng).stream()
                                .map(district -> new TimestampDistrict(latLng.timestamp, district))
                                .toList())
                .to("lightning_district", Produced.with(Serdes.String(), new JsonSerde<>(TimestampDistrict.class)));

        new KafkaStreams(builder.build(), props).start();

        while (true) Thread.sleep(Long.MAX_VALUE);
    }
}
