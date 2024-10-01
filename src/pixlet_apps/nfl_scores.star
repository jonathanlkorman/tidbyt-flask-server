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
DEFAULT_ROTATION_RATE = 10
DEFAULT_TEAMS = ["NYJ"]
DEFAULT_ROTATION_PREFERRED = False
DEFAULT_ROTATION_LIVE = True
DEFAULT_ROTATION_HIGHLIGHT = True

def main(config):
    location = config.get("location", DEFAULT_LOCATION)
    loc = json.decode(location)
    timezone = loc["timezone"]
    now = time.now().in_location(timezone)
    

    rotation_rate = config.get("rotation_rate", DEFAULT_ROTATION_RATE)
    preferred_teams = config.get("preferred_teams", DEFAULT_TEAMS)
    rotation_only_preferred = config.bool("rotation_only_preferred", DEFAULT_ROTATION_PREFERRED)
    rotation_only_live = config.bool("rotation_only_live", DEFAULT_ROTATION_LIVE)
    rotation_highlight_preferred_team_when_live = config.bool("rotation_highlight_preferred_team_when_live", DEFAULT_ROTATION_HIGHLIGHT)
    
    games = get_all_games()
    
    if not games:
        return render.Root(
            child = render.Text("No games available")
        )
    
    filtered_games = filter_games(games, preferred_teams, rotation_only_preferred, rotation_only_live, rotation_highlight_preferred_team_when_live)
    
    if not filtered_games:
        return render.Root(
            child = render.Text("No games match the criteria")
        )
    
    pages = []
    for game in filtered_games:
        pages.append(render_game(game, now, timezone))
    
    return render.Root(
        delay = int(rotation_rate) * 1000,
        show_full_animation = True,
        child = render.Animation(children = pages)
    )

def filter_games(games, preferred_teams, rotation_only_preferred, rotation_only_live, rotation_highlight_preferred_team_when_live):
    filtered_games = []
    for game in games:
        if rotation_only_preferred and not includes_preferred_team(game, preferred_teams):
            continue
        filtered_games.append(game)

    any_games_live = False
    for game in filtered_games:
        if is_live(game):
            any_games_live = True
            break

    if rotation_only_live and any_games_live:
        live_games = []
        for game in filtered_games:
            if is_live(game):
                live_games.append(game)
        filtered_games = live_games

    preferred_teams_live = False
    for game in filtered_games:
        if includes_preferred_team(game, preferred_teams) and is_live(game):
            preferred_teams_live = True
            break

    if rotation_highlight_preferred_team_when_live and preferred_teams_live:
        highlighted_games = []
        for game in filtered_games:
            if includes_preferred_team(game, preferred_teams) and is_live(game):
                highlighted_games.append(game)
        filtered_games = highlighted_games

    return filtered_games

def includes_preferred_team(game, preferred_teams):
    return game["hometeam"]["teamName"] in preferred_teams or game["awayteam"]["teamName"] in preferred_teams

def is_live(game):
    return game["state"] and game["state"] != "pre" and game["state"] != "post"

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
    total_width = 64
    total_height = 32
    first_column_width = int(total_width * 0.4375)
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
                child = render_team_row(
                    game, 
                    game["awayteam"], 
                    game["possession"] == game["awayteam"]["id"], 
                    width, 
                    team_height
                ),
            ),
            render.Box(
                width = width,
                height = team_height,
                child = render_team_row(
                    game, 
                    game["hometeam"], 
                    game["possession"] == game["hometeam"]["id"], 
                    width, 
                    team_height
                ),
            )
        ]
    )

def render_team_row(game, team, has_possession, width, height):
    team_color = get_team_color(team["teamName"], team["color"])
    
    # Calculate dimensions with padding
    padding = 1
    logo_size = height - (2 * padding)
    inner_width = width - (2 * padding)
    inner_height = height - (2 * padding)

    children = []

    children.append(
        render.Text(content = team["teamName"], font = "CG-pixel-3x5-mono", color = "#FFFFFF")
    )

    if game["state"] == "pre":
        children.append(
            render.Text(content = str(team["record"]), font = "tom-thumb", color = "#FFFFFF")
        )
    else:
        children.append(
            render.Text(content = str(team["score"]), font = "tom-thumb", color = "#FFFFFF")
        )
    
    if game["state"] == "in":
        children.append(
            render_timeout_indicators(team["timeouts"], team_color, inner_width - logo_size - 10)
        )  # 10 is an estimated width for the score/record text

    return render.Stack(
        children=[
            render.Box(
                width = width,
                height = height,
                color = team_color,
                
                child = render.Row(
                    expanded = True,
                    main_align = "space_around",
                    cross_align = "center",
                    children = [
                        render.Image(src = team["logo"], width = logo_size, height = logo_size),
                        render.Column(
                            expanded = True,
                            main_align = "space_around",
                            cross_align = "center",
                            children = children
                        ),
                    ]
                )
                
            ),
            render.Row(
                expanded=True,
                main_align="end",
                children=[
                    render.Column(
                        expanded=True,
                        main_align="center",
                        children=[
                            render.Box(height=2, width=2, color = "#FFFFFF" if has_possession else team_color),
                        ]
                    )
                ],
            ),
        ],
    )

def render_timeout_indicators(timeouts, team_color, width):
    indicators = []
    timeout_count = int(timeouts) if timeouts else 0
    indicator_width = 2
    spacing = 1 
    total_width = (indicator_width * 3) + (spacing * 2) 
    
    for i in range(3):
        color = "#FFFFFF" if i < timeout_count else "#000000"
        indicators.append(render.Box(width = indicator_width, height = 1, color = color))
        if i < 2:
            indicators.append(render.Box(width = spacing, height = 1, color = team_color))
    
    return render.Row(children = indicators, main_align = "end")
    
def render_game_status_column(game, now, timezone):
    status_lines = get_game_status(game, now, timezone)
    details = get_game_details(game)
    
    children = []
    
    if status_lines[0][0]:
        children.append(
            render.Text(content = status_lines[0][0], font = "tom-thumb", color = status_lines[0][1])
        )
    
    if status_lines[1][0]:
        children.append(
            render.Box(height=1, color="#000000")
        )
        children.append(
            render.Text(content = status_lines[1][0], font = "tom-thumb", color = status_lines[1][1])
        )
    
    if details[0][0]:
        children.append(
            render.Box(height=1, color="#000000")
        )
        children.append(
            render.Text(content = details[0][0], font = "tom-thumb", color = details[0][1])
        )

    if details[1][0]:
        children.append(
            render.Box(height=1, color="#000000")
        )
        children.append(
            render.Text(content = details[1][0], font = "tom-thumb", color = details[1][1])
        )
    
    return render.Column(
        expanded = True,
        main_align = "center",
        cross_align = "center",
        children = children
    )

def get_game_status(game, now, timezone):
    color = "#FF0000" if game["state"] == "post" else "#FFFFFF"

    gamedatetime = time.parse_time(game["date"], format="2006-01-02T15:04Z")
    local_gamedatetime = gamedatetime.in_location(timezone)
    
    if game["state"] == "pre":
        date_text = "TODAY" if local_gamedatetime.day == now.day else local_gamedatetime.format("Jan 2")
        gametime = local_gamedatetime.format("3:04 PM")
        return [(date_text, color), (gametime, color)]
    elif game["state"] == "post":
        date_text = local_gamedatetime.format("Jan 2")
        return [(date_text, "#FFFFFF"), ("Final", color)] if game["detail"] != "Final/OT" else [(date_text, "#FFFFFF"), ("F/OT", color)]
    else:
        return [(ORDINAL[game["quarter"]], color), (game["time"], color)]

def get_game_details(game):
    color = "#FFFFFF" 
    
    if game["state"] == "in":
        down = remove_lowercase_and_spaces(game["down"])
        return [(down, color), (game["spot"], color)]
    else:
        return [("", color), ("", color)]

def remove_lowercase_and_spaces(s):
    result = ""
    for i in range(len(s)):
        c = s[i]
        if c.isdigit() or c == "&":
            result += c
    return result.replace(" ", "")

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
            schema.Text(
                id = "preferred_teams",
                name = "Preferred Teams",
                desc = "Comma-separated list of preferred team abbreviations (e.g., 'NYG,DAL,GB')",
                icon = "star",
            ),
            schema.Text(
                id = "rotation_rate",
                name = "Rotation Rate",
                desc = "Number of seconds to display each game",
                icon = "star",
            ),
            schema.Toggle(
                id = "rotation_only_preferred",
                name = "Show Only Preferred Teams",
                desc = "If enabled, only shows games with preferred teams",
                icon = "eye",
                default = False,
            ),
            schema.Toggle(
                id = "rotation_only_live",
                name = "Show Only Live Games",
                desc = "If enabled, only shows live games when available",
                icon = "play",
                default = False,
            ),
            schema.Toggle(
                id = "rotation_highlight_preferred_team_when_live",
                name = "Highlight Preferred Teams When Live",
                desc = "If enabled, highlights preferred teams' games when they are live",
                icon = "highlighter",
                default = False,
            ),
        ],
    )