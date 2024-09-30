load("encoding/json.star", "json")
load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

CACHE_TTL_SECONDS = 300
DEFAULT_LOCATION = """
{
    "lat": "40.6781784",
    "lng": "-73.9441579",
    "description": "Brooklyn, NY, USA",
    "locality": "Brooklyn",
    "place_id": "ChIJCSF8lBZEwokRhngABHRcdoI",
    "timezone": "America/New_York"
}
"""
URL = "http://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard"
ORDINAL = ["Pre", "1st", "2nd", "3rd", "4th", "OT"]
ALT_COLOR = """
{
    "LAC": "1281c4",
    "LAR": "003594",
    "MIA": "008E97",
    "NO": "000000",
    "SEA": "002244",
    "TB": "34302B",
    "TEN": "0C2340"
}
"""

def main(config):
    location = config.get("location", DEFAULT_LOCATION)
    loc = json.decode(location)
    timezone = loc["timezone"]
    now = time.now().in_location(timezone)
    
    games = get_all_games()
    
    if not games:
        return render.Root(
            child = render.Text("No games available")
        )
    
    pages = []
    for game in games:
        pages.append(render_game(game, now, timezone))
    
    return render.Root(
        delay = int(10) * 1000,
        show_full_animation = True,
        child = render.Animation(children = pages)
    )

def get_all_games():
    res = http.get(URL)
    if res.status_code != 200:
        print("Error fetching game data")
        return []
    
    data = json.decode(res.body())
    games = []
    for event in data["events"]:
        info = event["competitions"][0]
        game = {
            "name": event["shortName"],
            "date": event["date"],
            "hometeam": parse_team(info["competitors"][0], True),
            "awayteam": parse_team(info["competitors"][1], False),
            "down": info.get("situation", {}).get("shortDownDistanceText"),
            "spot": info.get("situation", {}).get("possessionText"),
            "time": info["status"]["displayClock"],
            "quarter": info["status"]["period"],
            "over": info["status"]["type"]["completed"],
            "detail": info["status"]["type"]["detail"],
            "halftime": info["status"]["type"]["name"],
            "redzone": info.get("situation", {}).get("isRedZone"),
            "possession": info.get("situation", {}).get("possession"),
            "state": info["status"]["type"]["state"],
        }
        games.append(game)
    return games

def parse_score(score):
    if type(score) == "string":
        if score.isdigit():
            return int(score)
        else:
            return 0
    elif type(score) == "int":
        return score
    else:
        return 0  # Return 0 for any non-numeric or empty score

ALT_LOGO = """
{
    "IND": "https://i.ibb.co/jzMc7SB/colts.png"
}
"""

def get_logoType(team, logo):
    usealtlogo = json.decode(ALT_LOGO)
    usealt = usealtlogo.get(team, "NO")
    if usealt != "NO":
        logo = get_cachable_data(usealt, 36000)
    else:
        logo = logo.replace("500/scoreboard", "500-dark/scoreboard")
        logo = logo.replace("https://a.espncdn.com/", "https://a.espncdn.com/combiner/i?img=", 36000)
        logo = get_cachable_data(logo + "&h=50&w=50")
    return logo

def get_cachable_data(url, ttl_seconds = CACHE_TTL_SECONDS):
    res = http.get(url = url, ttl_seconds = ttl_seconds)
    if res.status_code != 200:
        fail("request to %s failed with status code: %d - %s" % (url, res.status_code, res.body()))
    return res.body()

def parse_team(team_data, is_home):
    logo_url = team_data["team"]["logo"] if "logo" in team_data["team"] else ""
    processed_logo = get_logoType(team_data["team"]["abbreviation"], logo_url)
    
    return {
        "teamName": team_data["team"]["abbreviation"],
        "id": team_data["id"],
        "score": parse_score(team_data.get("score", 0)),
        "timeouts": team_data.get("timeouts", 0),
        "color": team_data["team"]["color"],
        "altcolor": team_data["team"]["alternateColor"],
        "record": team_data["records"][0]["summary"] if "records" in team_data else None,
        "logo": processed_logo,
    }

def render_team_info(team, has_possession):
    team_color = get_team_color(team["teamName"], team["color"])
    possession_indicator = "◀" if has_possession else ""
    
    return render.Box(
        width = 64,
        height = 10,
        color = team_color,
        child = render.Row(
            expanded = True,
            main_align = "space_between",
            cross_align = "center",
            children = [
                render.Image(src = team["logo"], width = 10, height = 10),
                render.Text(content = team["teamName"], font = "tb-8", color = "#FFFFFF"),
                render.Text(content = team["record"] if team["record"] else str(team["score"]), font = "tb-8", color = "#FFFFFF"),
                render.Text(content = possession_indicator, font = "tb-8", color = "#FFFFFF"),
            ]
        )
    )

def render_game(game, now, timezone):
    return render.Column(
        children = [
            render_game_status(game, now, timezone),
            render_team_info(game["awayteam"], game["possession"] == game["awayteam"]["id"]),
            render_team_info(game["hometeam"], game["possession"] == game["hometeam"]["id"]),
            render_game_details(game),
        ]
    )

def render_game_status(game, now, timezone):
    if game["state"] == "pre":
        gamedatetime = time.parse_time(game["date"], format="2006-01-02T15:04Z")
        local_gamedatetime = gamedatetime.in_location(timezone)
        date_text = "TODAY" if local_gamedatetime.day == now.day else local_gamedatetime.format("Jan 2")
        gametime = local_gamedatetime.format("3:04 PM")
        status = date_text + " " + gametime
    elif game["state"] == "post":
        status = "Final" if game["detail"] != "Final/OT" else "F/OT"
    else:
        status = "%s %s" % (ORDINAL[game["quarter"]], game["time"])
    
    return render.Box(
        width = 64,
        height = 10,
        color = "#000000",
        child = render.Text(
            content = status,
            font = "tb-8",
            color = "#FFFFFF",
        )
    )

def render_game_details(game):
    if game["state"] == "in":
        return render.Box(
            width = 64,
            height = 8,
            color = "#000000",
            child = render.Text(
                content = "%s %s" % (game["down"], game["spot"]),
                font = "tb-8",
                color = "#FFFFFF",
            )
        )
    else:
        return render.Box(width = 64, height = 8)

def get_team_color(team_name, default_color):
    alt_colors = json.decode(ALT_COLOR)
    return "#" + alt_colors.get(team_name, default_color)

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Location(
                id = "location",
                name = "Location",
                desc = "Location for which to display time.",
                icon = "locationDot",
            ),
        ],
    )