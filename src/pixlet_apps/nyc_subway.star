"""
Applet: The Weekendest
Summary: The Weekendest - NYC subway
Description: Real-time New York City Subway projected departure times for a selected station, as seen on The Weekendest app. Takes into account of overnight and weekend service changes.
Author: blahblahblah-
"""

load("encoding/base64.star", "base64")
load("encoding/json.star", "json")
load("http.star", "http")
load("re.star", "re")
load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

DEFAULT_STOP_ID = "M16"
DEFAULT_DIRECTION = "both"
DEFAULT_TRAVEL_TIME = '{"display": "0", "value": "0", "text": "0"}'
GOOD_SERVICE_STOPS_URL_BASE = "https://goodservice.io/api/stops/"
GOOD_SERVICE_ROUTES_URL = "https://goodservice.io/api/routes/"

DISPLAY_ORDER_ETA = "eta"
DISPLAY_ORDER_ALPHABETICAL = "alphabetical"

NAME_OVERRIDE = {
    "Grand Central-42 St": "Grand Cntrl",
    "Times Sq-42 St": "Times Sq",
    "Coney Island-Stillwell Av": "Coney Is",
    "South Ferry": "S Ferry",
    "Mets-Willets Point": "Willets Pt",
}

STREET_ABBREVIATIONS = [
    "St",
    "Av",
    "Sq",
    "Blvd",
    "Rd",
    "Yards",
]

ABBREVIATIONS = {
    "World Trade Center": "Wld Trd Ctr",
    "Center": "Ctr",
    "Metropolitan": "Metrop",
    "Blvd": "Bl",
    "Park": "Pk",
    "Beach": "Bch",
    "Rockaway": "Rckwy",
    "Channel": "Chnl",
    "Green": "Grn",
    "Broadway": "Bway",
    "Queensboro": "Q Boro",
    "Plaza": "Plz",
    "Whitehall": "Whthall",
}

DIAMONDS = {
    "#00933c": "iVBORw0KGgoAAAANSUhEUgAAAAsAAAALCAYAAACprHcmAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAcElEQVQYlX3QsRHCMAxA0YcWAfagADaBleg5MgkciwRvQpNwjnCsTuf3C3njdpBmizuuKPVDNOATZ7ymvYlnuJ/2XQ5iBWoF0YF/QeDRgXUwhMbVjSm4BEYcO0HBCeN84Gcl+EGWX5eDBcy4Dt4ZwhdZ8R3soZmzOQAAAABJRU5ErkJggg==",
    "#b933ad": "iVBORw0KGgoAAAANSUhEUgAAAAsAAAALCAYAAACprHcmAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAc0lEQVQYlX3QwREBQRBA0acTQQwSQCYEpghAAE6URNZk4rKrZtvs9K1r3j/0rB67uzRrXHBGqR+iAZ844jXuTTzB7bhvchALUCuIDvwLAtcOrINbaFzdmIJTYMC+ExQcMEwHfhaCH2T+dTmYwYzr4J0hfAHfSh628EQX+AAAAABJRU5ErkJggg==",
    "#ff6319": "iVBORw0KGgoAAAANSUhEUgAAAAsAAAALCAYAAACprHcmAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAcElEQVQYlX3QwREBQRBA0aezcEImyAR5KSKhJLImEi67arbNTt+65v1Dz+pzWUuzwRVnlPohGvCBI57j3sQT3I37NgexALWC6MC/IHDrwDq4h8bVjSk4BQbsO0HBAcN04Hsh+EHmX5eDGcy4Dl4ZwhemXh6YbpNeCwAAAABJRU5ErkJggg==",
}

def main(config):
    routes_req = http.get(GOOD_SERVICE_ROUTES_URL)
    if routes_req.status_code != 200:
        fail("goodservice routes request failed with status %d", routes_req.status_code)

    stop_id = config.str("stop_id", DEFAULT_STOP_ID)
    stop_req = http.get(GOOD_SERVICE_STOPS_URL_BASE + stop_id + "?agent=tidbyt")
    if stop_req.status_code != 200:
        fail("goodservice stop request failed with status %d", stop_req.status_code)

    stops_req = http.get(GOOD_SERVICE_STOPS_URL_BASE)
    if stops_req.status_code != 200:
        fail("goodservice stops request failed with status %d", stops_req.status_code)

    travel_time_raw = json.decode(config.get("travel_time", DEFAULT_TRAVEL_TIME))["value"]
    if not is_parsable_integer(travel_time_raw):
        fail("non-integer value provided for travel_time: %s", travel_time_raw)
    travel_time_min = int(travel_time_raw)

    direction_config = config.str("direction", DEFAULT_DIRECTION)
    if direction_config == "both":
        directions = ["north", "south"]
    else:
        directions = [direction_config]

    ts = time.now().unix
    min_estimated_arrival_time = ts + (travel_time_min * 60)

    include_lines_str = config.str("include_lines", "").upper()
    include_lines = include_lines_str.split(",")

    all_upcoming_trains = []

    for dir in directions:
        dir_data = stop_req.json()["upcoming_trips"].get(dir)
        if not dir_data:
            continue

        for trip in dir_data:
            if trip["estimated_current_stop_arrival_time"] < min_estimated_arrival_time:
                continue

            route = routes_req.json()["routes"][trip["route_id"]]
            route_name = route["name"].upper()

            if include_lines_str and len(include_lines) and route_name not in include_lines:
                continue

            destination = None
            for s in stops_req.json()["stops"]:
                if s["id"] == trip["destination_stop"]:
                    destination = condense_name(s["name"])
                    break

            all_upcoming_trains.append({
                "route": route,
                "destination": destination,
                "arrival_time": trip["estimated_current_stop_arrival_time"],
                "is_delayed": trip["is_delayed"],
            })

    # Sort trains by arrival time and take the two soonest
    soonest_trains = sorted(all_upcoming_trains, key=lambda x: x["arrival_time"])[:2]

    if len(soonest_trains) == 0:
        return render.Root(
            child = render.Text("No trains found"),
        )

    blocks = []
    for i, train in enumerate(soonest_trains):
        route = train["route"]
        eta = (train["arrival_time"] - ts) / 60
        
        if train["is_delayed"]:
            text = "delay"
        elif eta < 1:
            text = "due"
        else:
            text = str(int(eta)) + " min"

        if len(route["name"]) > 1 and route["name"][1] == "X":
            bullet = render.Stack(
                children = [
                    render.Image(src = base64.decode(DIAMONDS[route["color"]])),
                    render.Padding(
                        pad = (4, 2, 0, 0),
                        child = render.Text(content = route["name"][0], color = route["text_color"] or "#fff", height = 8),
                    ),
                ],
            )
        else:
            bullet = render.Circle(
                color = route["color"],
                diameter = 11,
                child = render.Box(
                    padding = 1,
                    height = 11,
                    width = 11,
                    child = render.Text(
                        content = route["name"][0] if route["name"] != "SIR" else "SI",
                        color = route["text_color"] or "#fff",
                        height = 8,
                    ),
                ),
            )

        blocks.append(render.Row(
            main_align = "start",
            cross_align = "center",
            children = [
                render.Padding(pad = (1, 0, 1, 0), child = bullet),
                render.Column(
                    children = [
                        render.Text(train["destination"]),
                        render.Text(content = text, font = "tom-thumb", color = "#f2711c"),
                    ],
                ),
            ],
        ))

        # Add white line after the first train
        if i == 0:
            blocks.append(render.Box(width = 64, height = 1, color = "#FFFFFF"))

    return render.Root(
        child = render.Column(
            children = blocks,
        ),
        max_age = 60,
    )

def is_parsable_integer(maybe_number):
    return not re.findall("[^0-9]", maybe_number)

def travel_time_search(pattern):
    create_option = lambda value: schema.Option(display = value, value = value)

    if pattern == "0" or not is_parsable_integer(pattern):
        return [create_option(str(i)) for i in range(10)]

    int_pattern = int(pattern)
    if int_pattern > 60:
        return [create_option("60")]
    else:
        return [create_option(pattern)] + [create_option(pattern + str(i)) for i in range(10) if int_pattern * 10 + i < 60]

def get_schema():
    stops_req = http.get(GOOD_SERVICE_STOPS_URL_BASE)
    if stops_req.status_code != 200:
        fail("goodservice stops request failed with status %d", stops_req.status_code)

    stops_options = []

    for s in stops_req.json()["stops"]:
        stop_name = s["name"].replace(" - ", "-") + " - " + s["secondary_name"] if s["secondary_name"] else s["name"].replace(" - ", "-")
        routes = sorted(s["scheduled_routes"].keys())
        stops_options.append(
            schema.Option(
                display = stop_name + " (" + ", ".join(routes) + ")",
                value = s["id"],
            ),
        )

    return schema.Schema(
        version = "1",
        fields = [
            schema.Dropdown(
                id = "stop_id",
                name = "Station",
                desc = "Station to show subway departures",
                icon = "trainSubway",
                default = "M16",
                options = stops_options,
            ),
            schema.Dropdown(
                id = "direction",
                name = "Direction",
                desc = "Direction(s) of train depatures to be included",
                icon = "compass",
                default = "both",
                options = [
                    schema.Option(
                        display = "Both",
                        value = "both",
                    ),
                    schema.Option(
                        display = "Northbound",
                        value = "north",
                    ),
                    schema.Option(
                        display = "Southbound",
                        value = "south",
                    ),
                ],
            ),
            schema.Typeahead(
                id = "travel_time",
                name = "Travel Time to Station",
                desc = "Amount of time it takes to reach this station (trains with earlier arrival times will be hidden).",
                icon = "hourglass",
                handler = travel_time_search,
            ),
            schema.Dropdown(
                id = "third_time",
                name = "Third Time",
                desc = "3rd arrival time delta",
                icon = "hourglass",
                default = "3",
                options = [
                    schema.Option(
                        display = "OFF",
                        value = "0",
                    ),
                    schema.Option(
                        display = "3 mins",
                        value = "3",
                    ),
                    schema.Option(
                        display = "5 mins",
                        value = "5",
                    ),
                    schema.Option(
                        display = "7 mins",
                        value = "7",
                    ),
                    schema.Option(
                        display = "10 mins",
                        value = "10",
                    ),
                    schema.Option(
                        display = "Always Show",
                        value = "1000",
                    ),
                ],
            ),
            schema.Dropdown(
                id = "order_by",
                name = "Order By",
                desc = "The display order of train routes",
                icon = "sort",
                default = DISPLAY_ORDER_ETA,
                options = [
                    schema.Option(
                        display = "Next Train ETA",
                        value = DISPLAY_ORDER_ETA,
                    ),
                    schema.Option(
                        display = "Alphabetical Order",
                        value = DISPLAY_ORDER_ALPHABETICAL,
                    ),
                ],
            ),
            schema.Text(
                id = "include_lines",
                name = "Filter Lines",
                desc = "Only show certain lines (comma separated)",
                icon = "route",
                default = "",
            ),
        ],
    )

def condense_name(name):
    name = name.replace(" - ", "-")
    if len(name) < 11:
        return name

    if NAME_OVERRIDE.get(name):
        return NAME_OVERRIDE[name]

    if "-" in name:
        modified_name = name
        for abrv in STREET_ABBREVIATIONS:
            abbreviated_array = modified_name.split(abrv)
            modified_name = ""
            for a in abbreviated_array:
                modified_name = modified_name + a.strip()
        modified_name = modified_name.strip()
        if len(modified_name) < 11:
            return modified_name

    for key in ABBREVIATIONS:
        name = name.replace(key, ABBREVIATIONS[key])
    split_name = name.split("-")
    if len(split_name) > 1 and ("St" in split_name[1] or "Av" in split_name[1] or "Sq" in split_name[1] or "Bl" in split_name[1]) and (split_name[0] != "Far Rckwy"):
        if "Sts" in split_name[1]:
            return split_name[0] + " St"
        if "Avs" in split_name[1]:
            return split_name[0] + " Av"
        return split_name[1]
    return split_name[0]