load("encoding/json.star", "json")
load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

CACHE_TTL_SECONDS = 300

URL = "http://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard"

ORDINAL = ["Pre", "1st", "2nd", "3rd", "4th", "OT"]

WHITE = "#FFFFFF"
BLACK = "#000000"
RED = "#FF0000"

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

ALT_SIZE = """
{
    "IND": {"width": 12, "height": 12}
}
"""

DEFAULT_TIMEZONE = "America/New_York"
DEFAULT_ROTATION_RATE = 10
DEFAULT_TEAMS = ["NYJ"]
DEFAULT_ROTATION_PREFERRED = False
DEFAULT_ROTATION_LIVE = True
DEFAULT_ROTATION_HIGHLIGHT = True

def main(config):
    timezone = config.get("timezone", DEFAULT_TIMEZONE)
    now = time.now().in_location(timezone)
    
    rotation_rate = int(config.get("rotation_rate", DEFAULT_ROTATION_RATE))
    preferred_teams = config.get("preferred_teams", DEFAULT_TEAMS)
    rotation_only_preferred = config.bool("rotation_only_preferred", DEFAULT_ROTATION_PREFERRED)
    rotation_only_live = config.bool("rotation_only_live", DEFAULT_ROTATION_LIVE)
    rotation_highlight_preferred_team_when_live = config.bool("rotation_highlight_preferred_team_when_live", DEFAULT_ROTATION_HIGHLIGHT)
    
    games = get_all_games()
    
    if not games:
        return render.Root(child = render.Text("No games available"))
    
    filtered_games = filter_games(games, preferred_teams, rotation_only_preferred, rotation_only_live, rotation_highlight_preferred_team_when_live)
    
    if not filtered_games:
        return render.Root(child = render.Text("No games match the criteria"))
    
    pages = [render_game(game, now, timezone) for game in filtered_games]
    
    return render.Root(
        delay = rotation_rate * 1000,
        show_full_animation = True,
        child = render.Animation(children = pages)
    )

def filter_games(games, preferred_teams, rotation_only_preferred, rotation_only_live, rotation_highlight_preferred_team_when_live):
    filtered_games = [game for game in games if not rotation_only_preferred or includes_preferred_team(game, preferred_teams)]
    
    live_games = [game for game in filtered_games if is_live(game)]
    
    if rotation_only_live and live_games:
        filtered_games = live_games
    
    if rotation_highlight_preferred_team_when_live:
        preferred_live_games = [game for game in filtered_games if includes_preferred_team(game, preferred_teams) and is_live(game)]
        if preferred_live_games:
            filtered_games = preferred_live_games
    
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
            "hometeam": parse_team(info["competitors"][0], info.get('situation', {}).get('homeTimeouts', 0)),
            "awayteam": parse_team(info["competitors"][1], info.get('situation', {}).get('awayTimeouts', 0)),
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

def parse_team(team_data, timeouts):
    logo_url = team_data["team"]["logo"] if "logo" in team_data["team"] else ""
    team_abbr = team_data["team"]["abbreviation"]
    processed_logo = get_logoType(team_abbr, logo_url)
    logo_dimensions = get_logo_dimensions(team_abbr)
    
    return {
        "teamName": team_data["team"]["abbreviation"],
        "id": team_data["id"],
        "score": parse_score(team_data.get("score", 0)),
        "timeouts": timeouts,
        "color": team_data["team"]["color"],
        "altcolor": team_data["team"]["alternateColor"],
        "record": team_data["records"][0]["summary"] if "records" in team_data else None,
        "logo": processed_logo,
        "logo_width": logo_dimensions["width"],
        "logo_height": logo_dimensions["height"],
    }

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

def get_logo_dimensions(team):
    alt_sizes = json.decode(ALT_SIZE)
    default_size = {"width": 16, "height": 16}
    return alt_sizes.get(team, default_size)

def get_cachable_data(url, ttl_seconds = CACHE_TTL_SECONDS):
    res = http.get(url = url, ttl_seconds = ttl_seconds)
    if res.status_code != 200:
        fail("request to %s failed with status code: %d - %s" % (url, res.status_code, res.body()))
    return res.body()

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
    team_height = height // 2
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

    children = []

    children.append(
        render.Text(content = team["teamName"], font = "CG-pixel-3x5-mono", color = WHITE)
    )

    if game["state"] == "pre":
        children.append(
            render.Text(content = str(team["record"]), font = "tom-thumb", color = WHITE)
        )
    else:
        children.append(
            render.Text(content = str(team["score"]), font = "tom-thumb", color = WHITE)
        )
    
    if game["state"] == "in":
        children.append(
            render_timeout_indicators(team["timeouts"], team_color)
        )

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
                        render.Image(
                            src = team["logo"], 
                            width = team["logo_width"], 
                            height = team["logo_height"]
                        ),
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
                            render.Box(height=2, width=2, color = WHITE if has_possession else team_color),
                        ]
                    )
                ],
            ),
        ],
    )

def render_timeout_indicators(timeouts, team_color):
    indicators = []
    timeout_count = int(timeouts) if timeouts else 0
    indicator_width = 2
    spacing = 1 
    total_width = (indicator_width * 3) + (spacing * 2) 
    
    for i in range(3):
        color = WHITE if i < timeout_count else team_color
        indicators.append(render.Box(width = indicator_width, height = 1, color = color))
        if i < 2:
            indicators.append(render.Box(width = spacing, height = 1, color = team_color))
    
    return render.Row(children = indicators, main_align = "end")
    
def render_game_status_column(game, now, timezone):
    status = get_game_status(game, now, timezone)
    details = get_game_details(game)
    
    children = []
    
    if status.get("date_text"):
        children.append(
            render.Text(content=status["date_text"], font="tom-thumb", color=WHITE)
        )
        
    if status.get("gametime"):
        children.append(
            render.Box(height=1, color=BLACK)
        )
        children.append(
            render.Text(content=status["gametime"], font="tom-thumb", color=WHITE)
        )

    if status.get("final_text"):
        children.append(
            render.Box(height=1, color=BLACK)
        )
        children.append(
            render.Text(content=status["final_text"], font="tom-thumb", color=RED)
        )

    if status.get("quarter"):
        children.append(
            render.Box(height=1, color=BLACK)
        )
        children.append(
            render.Text(content=status["quarter"], font="tom-thumb", color=WHITE)
        )
        children.append(
            render.Box(height=1, color=BLACK)
        )
        children.append(
            render.Text(content=status["time"], font="tom-thumb", color=WHITE)
        )
    
    if details["down"]:
        children.append(
            render.Box(height=1, color=BLACK)
        )
        children.append(
            render.Text(content=details["down"], font="tom-thumb", color=WHITE)
        )

    if details["spot"]:
        children.append(
            render.Box(height=1, color=BLACK)
        )
        children.append(
            render.Text(content=details["spot"], font="tom-thumb", color=WHITE)
        )
    
    return render.Column(
        expanded=True,
        main_align="center",
        cross_align="center",
        children=children
    )


def get_game_status(game, now, timezone):
    gamedatetime = time.parse_time(game["date"], format="2006-01-02T15:04Z")
    local_gamedatetime = gamedatetime.in_location(timezone)
    
    if game["state"] == "pre":
        date_text = "TODAY" if local_gamedatetime.day == now.day else local_gamedatetime.format("Jan 2")
        gametime = local_gamedatetime.format("3:04 PM")
        return {
            "date_text": date_text, 
            "gametime": gametime
        }
    elif game["state"] == "post":
        date_text = local_gamedatetime.format("Jan 2")
        final_text = "Final" if game["detail"] != "Final/OT" else "F/OT"
        return {
            "date_text": date_text, 
            "final_text": final_text
        }
    else:
        time_text = "END" if game["time"] in ["0:00", "0:0", "0.00", "0.0"] else game["time"]
        return {
            "quarter": ORDINAL[game["quarter"]], 
            "time": time_text
        }

def get_game_details(game):    
    if game["state"] == "in" and game["down"]:
        down = remove_lowercase_and_spaces(game["down"])
        return {
            "down": down, 
            "spot": game["spot"]
        }
    else:
        return {
            "down": "", 
            "spot": ""
        }


def remove_lowercase_and_spaces(s):
    result = ""
    for i in range(len(s)):
        c = s[i]
        if c.isdigit() or c == "&" or c == 'G':
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