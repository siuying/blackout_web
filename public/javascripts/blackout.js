var Blackout = {};

Blackout.findCurrentLocation = function() {
	if (navigator.geolocation) {
		navigator.geolocation.getCurrentPosition(Blackout.onLocationFound, 
			Blackout.onNameNotFound, 
			{maximumAge:60000, timeout:10000});
	} else {
		Blackout.onPrefectureNotFound();
	}
};

Blackout.findNameByLocation = function(lat, lng) {
	var geocoder = new google.maps.Geocoder();
	var latlng = new google.maps.LatLng(lat, lng);
	geocoder.geocode({'latLng': latlng}, function(results, status) {

     if (status == google.maps.GeocoderStatus.OK) {
		var prefecture = null;
		var locality = null;
		var sublocality = null;
		var sublocality2 = null;

		for(i=0; i<status.length; i++) {
			var result = results[i];
			var isRoute = false;
			for(j=0; j<result["types"].length; j++) {
				var type = result["types"][j];
				if (type == "route") {
					isRoute = true;
				}
			}
			
			if (!isRoute) {
				var components = result["address_components"];
				for (k=0; k<components.length; k++) {
					var component = components[k];
					if (component.types && component.types[0] == "administrative_area_level_1" && !prefecture) {
						prefecture = component["long_name"];
					}
					if (component.types && component.types[0] == "locality" && !locality) {
						locality = component["long_name"];
					}
					if (component.types && component.types[0] == "sublocality_level_1" && !sublocality) {
						sublocality = component["long_name"];
					}
					if (component.types && component.types[0] == "sublocality_level_2" && !sublocality2) {
						sublocality2 = component["long_name"];
					}
				}
				if (prefecture && sublocality && sublocality2 && locality) break;
			}
		}
		
		if (prefecture) {
			if (sublocality2) 
				sublocality = sublocality + "" + sublocality2
			Blackout.onNameFound(prefecture, locality, sublocality);
		} else {
			Blackout.onNameNotFound();
		}
     }
   });
}

/* callbacks */
Blackout.onLocationFound = function(lat, lng) {
	var lat = location.coords.latitude;
	var lng = location.coords.longitude;
	Blackout.findNameByLocation(lat, lng);
};

Blackout.onNameFound = function(prefecture, locality, sublocality) {
	console.log(prefecture, locality, sublocality);
};

Blackout.onNameNotFound = function() {
	console.log("location not found");
};
