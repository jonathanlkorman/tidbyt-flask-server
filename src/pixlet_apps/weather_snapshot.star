load("encoding/base64.star", "base64")
load("encoding/json.star", "json")
load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

# Constants
CACHE_TTL_SEC = 6 * 60 * 60  # 6 hours cache

NWS_FORECAST_URL = "https://api.weather.gov/gridpoints/{}/{},{}/forecast"

DEFAULT_LOCATION = """
{
    "grid_id": "OKX",
    "grid_x": "39",
    "grid_y": "36"
}
"""

# Color Constants
COLOR_SCHEME = {
    "HIGH_TEMP": "#fcb1b1",
    "LOW_TEMP": "#abb7f7",
}

# Icon Base64 Encodings
WEATHER_ICONS = {
    "SUN": "iVBORw0KGgoAAAANSUhEUgAAAA0AAAALCAYAAACksgdhAAAAAXNSR0IArs4c6QAAAIVJREFUKFNjZMAC/l9i+M+ox8CITQ4khlWCKE2EFKHbCLcJphFEwxTd57mHol5JSQmsHsV5+DTAdIM0MsIUgjwOY6PbgNN59+7dgzsLWdHu3zxgrivrF7gw2HmENMBUwzQywjTATISZisxHthmkEWzTzJuvsDoNW+Smq4sx4ox1XKkBJA4AoH84cEr5M3wAAAAASUVORK5CYII=",
    "SUN_CLOUDS": "iVBORw0KGgoAAAANSUhEUgAAAA0AAAALCAYAAACksgdhAAAAAXNSR0IArs4c6QAAAIVJREFUKFNjZMAC/l9i+M+ox8CITQ4khlWCKE2EFKHbCLcJphFEwxTd57mHol5JSQmsHsV5+DT...rest_of_icon_data",
    "CLOUDS": "iVBORw0KGgoAAAANSUhEUgAAAA0AAAALCAYAAACksgdhAAAAAXNSR0IArs4c6QAAAGdJREFUKFNjZCADMJKhhwGvpnv37v1HNlRJSQmsHqcmdA0wzSCNWDXh0gDTCNeES+Hu3zxgta6sX+AuBWsipAGmGqaREaYBZiLMVGQ+cmCANIJtmnnzFUoo4YuGdHUx7AFBKO7IilwAmVomcJu9o24AAAAASUVORK5CYII=",
    "GRAY_CLOUDS": "iVBORw0KGgoAAAANSUhEUgAAAA0AAAALCAYAAACksgdhAAAAAXNSR0IArs4c6QAAAGVJREFUKFOd0UEKACEIBdC8ikvP4nE7i8uuMkPCD2fIAtsF/1n4qRUOFUw7ojHGE4cys+dT9AfAE25RBgAXyoJm5lkRWT91dANIAxIAJmJqvMdlTOgv9d4/WzrVoKr7Rdy6K5X7ArtaJnAgKPSJAAAAAElFTkSuQmCC",
    "RAIN": "iVBORw0KGgoAAAANSUhEUgAAAA0AAAALCAYAAACksgdhAAAAAXNSR0IArs4c6QAAAHpJREFUKFOFkcENwCAIRWWEruDRTZo4Lkk38cgKHcFGkm+gQeWgQf5D/FLahIh0W84508h1ieIPQDPAEFoBACe0ErbWVFtKmQMpdAKgBkgA0BFdbW7fPEC9iZmdSztHa62xETvIW/68Pd0XpdPu/ukkRj2EMJsR6ZHJP9b5TXASHYv4AAAAAElFTkSuQmCC",
    "SNOW": "iVBORw0KGgoAAAANSUhEUgAAAA0AAAALCAYAAACksgdhAAAAAXNSR0IArs4c6QAAAG9JREFUKFOFkcENACEIBI9WfFKL5VKLT1rhIsl66CnyMNm4A7jSk5SqWrwupVDXfuxqBeDp4BY6AQAHdDK21tzLzGMhh24A3AAJADqia9TxzR30SSIypZQlWmvdB5FBU+RmZkRfk0z/Ir/B6edmK75T6Tpw9IEWMAAAAABJRU5ErkJggg=="
}

def get_day_abbreviation(full_name):
    if full_name in ["Today", "This Afternoon", "Tonight"]:
        full_name = time.now().format("Monday")
    
    day_abbr = {
        'Monday': 'MON', 
        'Tuesday': 'TUE', 
        'Wednesday': 'WED', 
        'Thursday': 'THU', 
        'Friday': 'FRI', 
        'Saturday': 'SAT', 
        'Sunday': 'SUN'
    }
    return day_abbr.get(full_name, full_name)

def validate_forecast_response(response):
    if response.status_code != 200:
        fail("Forecast request failed with status" + str(response.status_code))

def fetch_forecast_data(grid_id, grid_x,grid_y):
    url = NWS_FORECAST_URL.format(grid_id, grid_x, grid_y)
    response = http.get(url, ttl_seconds=CACHE_TTL_SEC)
    validate_forecast_response(response)
    return response.json()

def get_forecast_icon(short_forecast):
    short_forecast = short_forecast.lower()
    
    if "rain" in short_forecast or "showers" in short_forecast:
        return WEATHER_ICONS["RAIN"]
    elif "snow" in short_forecast:
        return WEATHER_ICONS["SNOW"]
    elif "sunny" in short_forecast or "clear" in short_forecast:
        return WEATHER_ICONS["SUN"]
    elif "partly sunny" in short_forecast or "partly cloudy" in short_forecast:
        return WEATHER_ICONS["SUN_CLOUDS"]
    elif "cloudy" in short_forecast:
        return WEATHER_ICONS["CLOUDS"]
    else:
        return WEATHER_ICONS["GRAY_CLOUDS"]

def get_high_low_temps(periods):
    if not periods:
        return {"high": "--", "low": "--"}

    current_day_periods = []
    current_date = time.now().format("YYYY-MM-DD")

    for period in periods:
        period_date = period["startTime"][:10]
        if period_date == current_date:
            current_day_periods.append(period)

    if not current_day_periods:
        current_day_periods = periods[:2]

    day_periods = [p for p in current_day_periods if p.get("isDaytime", False)]
    night_periods = [p for p in current_day_periods if not p.get("isDaytime", False)]

    high_temp = "--"
    low_temp = "--"

    if day_periods and "temperature" in day_periods[0]:
        high_temp = str(int(day_periods[0]["temperature"]))
    elif current_day_periods and "temperature" in current_day_periods[0]:
        high_temp = str(int(current_day_periods[0]["temperature"]))

    if night_periods and "temperature" in night_periods[0]:
        low_temp = str(int(night_periods[0]["temperature"]))
    elif len(current_day_periods) > 1 and "temperature" in current_day_periods[1]:
        low_temp = str(int(current_day_periods[1]["temperature"]))

    return {
        "high": high_temp, 
        "low": low_temp
    }

def render_forecast_column(forecast_periods_subset):
    temps = get_high_low_temps(forecast_periods_subset)
    
    return render.Column(
        main_align = "center",
        cross_align = "center",
        children = [
            render.Image(src = base64.decode(get_forecast_icon(forecast_periods_subset[0]["shortForecast"]))),
            render.Padding(
                pad = (0, 3, 0, 3),
                child = render.Text(font = "CG-pixel-3x5-mono", content = forecast_periods_subset[0]["name"]),
            ),
            render.Row(
                expanded = False,
                children = [
                    render.Padding(
                        pad = (0, 0, 1, 0),
                        child = render.Text(font = "CG-pixel-3x5-mono", color = COLOR_SCHEME["HIGH_TEMP"], content = temps["high"]),
                    ),
                    render.Text(font = "CG-pixel-3x5-mono", color = COLOR_SCHEME["LOW_TEMP"], content = temps["low"]),
                ]
            ),
        ],
    )

def main(config):
    location = config.get("location", DEFAULT_LOCATION)
    location_dict = json.decode(location)
    grid_id = location_dict.get("grid_id")
    grid_x = location_dict.get("grid_x")
    grid_y = location_dict.get("grid_y")

    forecast_data = fetch_forecast_data(grid_id, grid_x, grid_y)
    forecast_periods = forecast_data["properties"]["periods"]
    
    if not forecast_periods:
        return render.Root(
            child = render.Text(content = "No forecast data")
        )
    
    for period in forecast_periods:
        period["name"] = get_day_abbreviation(period["name"])
    
    display_period_subsets = [
        forecast_periods[0:2], 
        forecast_periods[2:4], 
        forecast_periods[4:6]
    ]
    
    return render.Root(
        child = render.Box(
            render.Row(
                expanded = True,
                main_align = "space_around",
                children = [
                    render_forecast_column(period_subset) for period_subset in display_period_subsets
                ],
            ),
        ),
    )