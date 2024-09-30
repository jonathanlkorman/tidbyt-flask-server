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

ALT_LOGO = """
{
    "IND": "https://i.ibb.co/jzMc7SB/colts.png"
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
        return 0

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


def render_game(game, now, timezone):
    # Calculate column widths
    total_width = 64
    total_height = 32
    first_column_width = 28
    second_column_width = total_width - first_column_width

    return render.Row(
        expanded = True,
        children = [
            render.Box(
                width = first_column_width,
                height = total_height,
                child = render_game_status_column(game, now, timezone)
            ),
            render.Box(
                width = second_column_width,
                height = total_height,
                child = render_team_info_column(game, second_column_width, total_height)
            ),
        ]
    )

def render_team_info_column(game, width, height):
    team_height = height // 2  # Each team takes up half the height
    return render.Column(
        expanded = True,
        children = [
            render.Box(
                width = width,
                height = team_height,
                child = render_team_row(game, game["awayteam"], game["possession"] == game["awayteam"]["id"], width, team_height),
            ),
            render.Box(
                width = width,
                height = team_height,
                child = render_team_row(game, game["hometeam"], game["possession"] == game["hometeam"]["id"], width, team_height),
            )
        ]
    )

def render_team_row(game, team, has_possession, width, height):
    team_color = get_team_color(team["teamName"], team["color"])
    possession_indicator = "◀" if has_possession else ""
    
    # Calculate dimensions with padding
    padding = 1
    logo_size = height - (2 * padding)
    inner_width = width - (2 * padding)
    inner_height = height - (2 * padding)

    children = []

    children.append(render.Text(content = team["teamName"], font = "tom-thumb", color = "#FFFFFF"))

    if game["state"] == "pre":
        children.append(render.Text(content = str(team["record"]), font = "tom-thumb", color = "#FFFFFF"))
    else:
        children.append(render.Text(content = str(team["score"]), font = "tom-thumb", color = "#FFFFFF"))
    
    return render.Box(
        width = width,
        height = height,
        color = team_color,
        child = render.Padding(
            pad = (padding, padding, padding, padding),
            child = render.Row(
                expanded = True,
                main_align = "space_between",
                cross_align = "center",
                children = [
                    render.Image(src = team["logo"], width = logo_size, height = logo_size),
                    render.Column(
                        expanded = True,
                        main_align = "center",
                        cross_align = "center",
                        children = children
                    ),
                    render.Text(content = possession_indicator, font = "tom-thumb", color = "#FFFFFF"),
                ]
            )
        )
    )

def render_game_status_column(game, now, timezone):
    status_lines = get_game_status(game, now, timezone)
    details = get_game_details(game)
    
    children = []
    
    if status_lines[0][0]:
        children.append(render.Text(content = status_lines[0][0], font = "tom-thumb", color = status_lines[0][1]))
    
    if status_lines[1][0]:
        children.append(render.Text(content = status_lines[1][0], font = "tom-thumb", color = status_lines[1][1]))
    
    if details[0]:
        children.append(render.Text(content = details[0], font = "tom-thumb", color = details[1]))
    
    return render.Column(
        expanded = True,
        main_align = "center",
        cross_align = "center",
        children = children
    )


def get_game_status(game, now, timezone):
    color = "#FF0000" if game["state"] == "post" else "#FFFFFF"
    
    if game["state"] == "pre":
        gamedatetime = time.parse_time(game["date"], format="2006-01-02T15:04Z")
        local_gamedatetime = gamedatetime.in_location(timezone)
        date_text = "TODAY" if local_gamedatetime.day == now.day else local_gamedatetime.format("Jan 2")
        gametime = local_gamedatetime.format("3:04 PM")
        return [(date_text, color), (gametime, color)]
    elif game["state"] == "post":
        return [("Final", color), ("", color)] if game["detail"] != "Final/OT" else [("F/OT", color), ("", color)]
    else:
        return [(ORDINAL[game["quarter"]], color), (game["time"], color)]

def get_game_details(game):
    color = "#FFFFFF" 
    
    if game["state"] == "in":
        return ("%s %s" % (game["down"], game["spot"]), color)
    else:
        return ("", color)

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