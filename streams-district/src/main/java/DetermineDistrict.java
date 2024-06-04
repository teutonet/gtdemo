import org.geotools.api.feature.simple.SimpleFeature;
import org.geotools.data.simple.SimpleFeatureCollection;
import org.geotools.data.simple.SimpleFeatureIterator;
import org.geotools.filter.FilterFactoryImpl;
import org.locationtech.jts.geom.Coordinate;
import org.locationtech.jts.geom.GeometryFactory;

import java.io.IOException;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

import static java.nio.file.Files.readString;
import static org.geotools.data.geojson.GeoJSONReader.parseFeatureCollection;

public class DetermineDistrict {

    public static final GeometryFactory GEOMETRY_FACTORY = new GeometryFactory();
    public static final SimpleFeatureCollection DISTRICTS;
    public static final FilterFactoryImpl FILTER_FACTORY = new FilterFactoryImpl();

    static {
        try {
            DISTRICTS = parseFeatureCollection(readString(Path.of(System.getenv("DISTRICTS_GEOJSON"))));
        } catch (IOException e) {
            throw new RuntimeException(e);
        }
    }

    public static List<String> determineDistricts(double lat, double lng) {
        SimpleFeatureIterator matchingDistricts = DISTRICTS.subCollection(
                        FILTER_FACTORY.intersects(
                                DISTRICTS.getSchema().getGeometryDescriptor().getLocalName(),
                                GEOMETRY_FACTORY.createPoint(new Coordinate(lng, lat))))
                .features();
        ArrayList<String> result = new ArrayList<>();
        while (matchingDistricts.hasNext()) {
            SimpleFeature feature = matchingDistricts.next();
            if ("Gütersloh".equals(feature.getAttribute("Gemeinde").toString()))
                result.add(feature.getAttribute("Gemarkung").toString());
        }
        return result;
    }
}
