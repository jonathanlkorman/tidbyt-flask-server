import json
from itertools import groupby
from operator import itemgetter
import requests
from datetime import datetime, timedelta
from google.transit import gtfs_realtime_pb2
from dataclasses import dataclass
from collections import defaultdict
import heapq
import logging
import pytz

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

@dataclass
class TrainInfo:
    departure_time: datetime
    arrival_time: datetime
    route_id: str
    direction_id: int
    from_station: str
    to_station: str
    trip_id: str 
    route_text_color: str
    route_color: str
    route_name: str

    def __lt__(self, other):
        return self.departure_time < other.departure_time

LIRR_STATIONS = {
    "Albertson": "1",
    "Amagansett": "4",
    "Amityville": "8",
    "Atlantic Terminal": "241",
    "Auburndale": "2",
    "Babylon": "27",
    "Baldwin": "225",
    "Bay Shore": "26",
    "Bayside": "25",
    "Bellerose": "23",
    "Bellmore": "16",
    "Belmont Park": "24",
    "Bethpage": "20",
    "Brentwood": "29",
    "Bridgehampton": "13",
    "Broadway": "11",
    "Carle Place": "39",
    "Cedarhurst": "32",
    "Central Islip": "33",
    "Centre Avenue": "31",
    "Cold Spring Harbor": "40",
    "Copiague": "38",
    "Country Life Press": "36",
    "Deer Park": "44",
    "Douglaston": "42",
    "East Hampton": "48",
    "East New York": "50",
    "East Rockaway": "51",
    "East Williston": "52",
    "Elmont-UBS Arena": "359",
    "Far Rockaway": "65",
    "Farmingdale": "59",
    "Floral Park": "63",
    "Flushing Main Street": "56",
    "Forest Hills": "55",
    "Freeport": "64",
    "Garden City": "68",
    "Gibson": "66",
    "Glen Cove": "67",
    "Glen Head": "71",
    "Glen Street": "76",
    "Grand Central": "349",
    "Great Neck": "72",
    "Great River": "74",
    "Greenlawn": "78",
    "Greenport": "73",
    "Greenvale": "77",
    "Hampton Bays": "83",
    "Hempstead": "84",
    "Hempstead Gardens": "85",
    "Hewlett": "94",
    "Hicksville": "92",
    "Hillside Facility": "86",
    "Hollis": "89",
    "Hunterspoint Avenue": "90",
    "Huntington": "91",
    "Inwood": "101",
    "Island Park": "99",
    "Islip": "100",
    "Jamaica": "102",
    "Kew Gardens": "107",
    "Kings Park": "111",
    "Lakeview": "124",
    "Laurelton": "122",
    "Lawrence": "114",
    "Lindenhurst": "117",
    "Little Neck": "120",
    "Locust Manor": "119",
    "Locust Valley": "123",
    "Long Beach": "113",
    "Long Island City": "118",
    "Lynbrook": "125",
    "Malverne": "142",
    "Manhasset": "131",
    "Massapequa": "136",
    "Massapequa Park": "135",
    "Mastic-Shirley": "140",
    "Mattituck": "126",
    "Medford": "129",
    "Merillon Avenue": "127",
    "Merrick": "226",
    "Mets-Willets Point": "199",
    "Mineola": "132",
    "Montauk": "141",
    "Murray Hill": "130",
    "Nassau Boulevard": "149",
    "New Hyde Park": "152",
    "Northport": "153",
    "Nostrand Avenue": "148",
    "Oakdale": "157",
    "Oceanside": "155",
    "Oyster Bay": "154",
    "Patchogue": "163",
    "Penn Station": "237",
    "Pinelawn": "165",
    "Plandome": "162",
    "Port Jefferson": "164",
    "Port Washington": "171",
    "Queens Village": "175",
    "Riverhead": "176",
    "Rockville Centre": "183",
    "Ronkonkoma": "179",
    "Rosedale": "180",
    "Roslyn": "182",
    "Sayville": "204",
    "Sea Cliff": "185",
    "Seaford": "187",
    "Southampton": "191",
    "Southold": "190",
    "Speonk": "198",
    "St. Albans": "184",
    "St. James": "193",
    "Stewart Manor": "195",
    "Stony Brook": "14",
    "Syosset": "205",
    "Valley Stream": "211",
    "Wantagh": "215",
    "West Hempstead": "216",
    "Westbury": "213",
    "Westhampton": "233",
    "Westwood": "219",
    "Woodmere": "217",
    "Woodside": "214",
    "Wyandanch": "220",
    "Yaphank": "223"
}

ROUTE_COLORS = {
    "1": {"name": "Babylon Branch", "color": "00985F", "text_color": "FFFFFF"},
    "2": {"name": "Hempstead Branch", "color": "CE8E00", "text_color": "121212"},
    "3": {"name": "Oyster Bay Branch", "color": "00AF3F", "text_color": "FFFFFF"},
    "4": {"name": "Ronkonkoma Branch", "color": "A626AA", "text_color": "FFFFFF"},
    "5": {"name": "Montauk Branch", "color": "00B2A9", "text_color": "121212"},
    "6": {"name": "Long Beach Branch", "color": "FF6319", "text_color": "FFFFFF"},
    "7": {"name": "Far Rockaway Branch", "color": "6E3219", "text_color": "FFFFFF"},
    "8": {"name": "West Hempstead Branch", "color": "00A1DE", "text_color": "121212"},
    "9": {"name": "Port Washington Branch", "color": "C60C30", "text_color": "FFFFFF"},
    "10": {"name": "Port Jefferson Branch", "color": "006EC7", "text_color": "FFFFFF"},
    "11": {"name": "Belmont Park", "color": "60269E", "text_color": "FFFFFF"},
    "12": {"name": "City Terminal Zone", "color": "4D5357", "text_color": "FFFFFF"}
}

DEFAULT_FROM_STATION = "Forest Hills"
DEFAULT_TO_STATION = "Penn Station"

def get_route_info(route_id):
    route_info = ROUTE_COLORS.get(route_id, {
        "name": "Unknown Route",
        "color": "CCCCCC",
        "text_color": "000000"
    })
    return route_info

def get_station_name(station_id):
    return next((name for name, id in LIRR_STATIONS.items() if id == station_id), None)

def get_station_id(station_name):
    return LIRR_STATIONS.get(station_name)

def fetch_train_times(start_station, end_station, include_transfers=True, max_search_time=timedelta(hours=6)):
    url = 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/lirr%2Fgtfs-lirr'
    
    try:
        response = requests.get(url)
        response.raise_for_status()
    except requests.RequestException as e:
        logging.error(f"Error fetching GTFS real-time data: {e}")
        return []

    feed = gtfs_realtime_pb2.FeedMessage()
    feed.ParseFromString(response.content)

    trips = parse_feed(feed)
    #logging.info(f"Parsed {len(trips)} trips from feed")
    
    graph = build_graph(trips)
    #logging.info(f"Built graph with {len(graph)} stations")
    
    start_time = datetime.now()
    routes = find_routes(graph, get_station_id(start_station), get_station_id(end_station), start_time, max_search_time)
    #logging.info(f"Found {len(routes)} routes from {start_station} to {end_station}")
    
    return process_routes(routes, include_transfers, get_station_id(end_station))

def parse_feed(feed):
    trips = []
    for entity in feed.entity:
        if entity.HasField('trip_update'):
            trip = entity.trip_update
            stops = sorted(trip.stop_time_update, key=lambda x: x.stop_sequence)
            for i in range(len(stops) - 1):
                from_stop = stops[i]
                to_stop = stops[i + 1]
                if from_stop.HasField('departure') and to_stop.HasField('arrival'):
                    route_info = get_route_info(trip.trip.route_id)
                    train_info = TrainInfo(
                        departure_time=datetime.fromtimestamp(from_stop.departure.time),
                        arrival_time=datetime.fromtimestamp(to_stop.arrival.time),
                        route_id=trip.trip.route_id,
                        direction_id=trip.trip.direction_id,
                        from_station=from_stop.stop_id,
                        to_station=to_stop.stop_id,
                        trip_id=trip.trip.trip_id,
                        route_color=route_info["color"],
                        route_text_color=route_info["text_color"],
                        route_name=route_info["name"]
                    )
                    trips.append(train_info)
    return trips

def build_graph(trips):
    graph = defaultdict(list)
    for trip in trips:
        graph[trip.from_station].append(trip)
    return graph

def find_routes(graph, start, end, start_time, max_search_time):
    heap = [(start_time, [], start, set())]
    routes = []
    visited = set()
    end_time = start_time + max_search_time
    
    while heap:
        (time, path, station, visited_stations) = heapq.heappop(heap)
        
        if time > end_time:
            #logging.info("Reached maximum search time")
            break
        
        if station == end:
            #logging.info(f"Found route to destination: {[t.from_station for t in path] + [end]}")
            routes.append(path)
            continue
        
        if (station, time.date()) in visited:
            continue
        
        visited.add((station, time.date()))
        
        for trip in graph[station]:
            if trip.departure_time >= time and trip.to_station not in visited_stations:
                new_path = path + [trip]
                new_visited = visited_stations.union({trip.to_station})
                heapq.heappush(heap, (trip.arrival_time, new_path, trip.to_station, new_visited))
    
    return routes

def process_routes(routes, include_transfers, end_station):
    processed_routes = []
    for route in routes:
        processed_route = []
        current_trip = None
        valid_route = True
        for trip in route:
            if current_trip is None:
                current_trip = trip
            elif trip.from_station == current_trip.to_station:
                # Valid transfer or continuation of the same trip
                if trip.trip_id != current_trip.trip_id:
                    processed_route.append(current_trip)
                    current_trip = trip
                else:
                    # Same trip, update the end station and time
                    current_trip.to_station = trip.to_station
                    current_trip.arrival_time = trip.arrival_time
            else:
                # Invalid transfer
                valid_route = False
                break
        
        if valid_route and current_trip:
            processed_route.append(current_trip)
        
        if processed_route and processed_route[-1].to_station == end_station:
            transfers = len(processed_route) - 1
            total_time = processed_route[-1].arrival_time - processed_route[0].departure_time
            processed_routes.append((processed_route, transfers, total_time))

    # Group routes by starting train (first trip's from_station and departure_time)
    grouped_routes = groupby(
        sorted(processed_routes, key=lambda r: (r[0][0].from_station, r[0][0].departure_time)),
        key=lambda r: (r[0][0].from_station, r[0][0].departure_time)
    )

    # Select the fastest route for each starting train
    best_routes = [min(group, key=itemgetter(2)) for _, group in grouped_routes]

    # Sort routes by departure time
    best_routes.sort(key=lambda r: r[0][0].departure_time)

    # If include_transfers is False, filter out routes with transfers
    if not include_transfers:
        no_transfer_routes = [route for route in best_routes if route[1] == 0]
        final_routes = no_transfer_routes if no_transfer_routes else best_routes
    else:
        final_routes = best_routes

    return final_routes

def route_to_dict(route_info):
    route, transfers, total_time = route_info
    
    departure_time = route[0].departure_time
    ny_tz = pytz.timezone('America/New_York')
    ny_time = departure_time.astimezone(ny_tz)
    formatted_departure_time = ny_time.strftime("%I:%M %p")

    return {
        "destination_station_name": get_station_name(route[0].to_station),
        "route_name": route[0].route_name,
        "route_text_color": route[0].route_text_color,
        "route_color": route[0].route_color,
        "departure_time": formatted_departure_time,
        "total_time": str(total_time),
        "is_direct": transfers == 0
    }

def routes_to_json(routes):
    routes_dict = [route_to_dict(route) for route in routes]
    return json.dumps(routes_dict)

def get_trains(start_station, end_station):
    include_transfers = False
    routes = fetch_train_times(start_station, end_station, include_transfers)
    return routes_to_json(routes)

def get_data(config):
    """
    Main function to get LIRR data based on input parameters.
    This function will be called by the Flask app.
    
    :param config: Dictionary containing configuration from the Starlark app
    :return: Dictionary containing the list of LIRR trains
    """
    try:
        from_station = config.get('from', DEFAULT_FROM_STATION)
        to_station = config.get('to', DEFAULT_TO_STATION)

        trains = get_trains(from_station, to_station)
        
        return {"trains": trains}
    
    except Exception as e:
        return {"error": str(e)}