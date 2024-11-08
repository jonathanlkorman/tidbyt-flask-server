load("encoding/json.star", "json")
load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

CACHE_TTL_SECONDS = 300

TEAM_MAP = {
    "NYI": "12",   
}

SCOREBOARD_URL = "http://site.api.espn.com/apis/site/v2/sports/hockey/nhl/scoreboard"
SCHEDULE_URL = "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/teams/team_id/schedule"

ORDINAL = ["Pre", "1st", "2nd", "3rd", "OT"]

WHITE = "#FFFFFF"
BLACK = "#000000"
RED = "#FF0000"
GREY = "#6b6b6b"

ALT_LOGO = """
{
    "AAA": "https://i.ibb.co/jzMc7SB/colts.png"
}
"""
DEFAULT_TIMEZONE = "America/New_York"
DEFAULT_CUTOFF_TIME = 9
DEFAULT_ROTATION_RATE = 10
DEFAULT_TEAMS = ["NYI"]
DEFAULT_ROTATION_PREFERRED = False
DEFAULT_ROTATION_LIVE = True
DEFAULT_ROTATION_HIGHLIGHT = True
DEFAULT_SINGLE_GAME_MODE = False

def main(config):
    timezone = config.get("timezone", DEFAULT_TIMEZONE)
    cutoff_time = config.get("cutoff_time", DEFAULT_CUTOFF_TIME)
    now = time.now().in_location(timezone)
    
    single_game_mode = config.get("single_game_mode", DEFAULT_SINGLE_GAME_MODE)
    rotation_rate = int(config.get("rotation_rate", DEFAULT_ROTATION_RATE))
    preferred_teams = config.get("preferred_teams", DEFAULT_TEAMS)
    rotation_only_preferred = config.bool("rotation_only_preferred", DEFAULT_ROTATION_PREFERRED)
    rotation_only_live = config.bool("rotation_only_live", DEFAULT_ROTATION_LIVE)
    rotation_highlight_preferred_team_when_live = config.bool("rotation_highlight_preferred_team_when_live", DEFAULT_ROTATION_HIGHLIGHT)
    
    if single_game_mode and len(preferred_teams) == 1: 
        team_id = TEAM_MAP.get(preferred_teams[0])
        next_game_day = get_next_game_date(team_id, cutoff_time, timezone)
        game = get_next_game(cutoff_time, timezone, team_id, next_game_day)
        
        if not game:
            return render.Root(child = render.Text("No games available for the selected team"))
            
        return render.Root(child = render_game(game, now, timezone, 1, 0))


    games = get_all_games(cutoff_time, timezone)
    
    if not games:
        return render.Root(child = render.Text("No games available"))
    
    filtered_games = filter_games(games, preferred_teams, rotation_only_preferred, rotation_only_live, rotation_highlight_preferred_team_when_live)
    
    if not filtered_games:
        return render.Root(child = render.Text("No games match the criteria"))
    
    game_count = len(filtered_games)
    
    pages = [render_game(game, now, timezone, game_count, index) for index, game in enumerate(filtered_games)]
    
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

def get_all_games(cutoff_time,  timezone):
    res = http.get(SCOREBOARD_URL + "?dates=" + get_date_string(get_cutoff_date(cutoff_time, timezone)))
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
            "hometeam": parse_team(info["competitors"][0]),
            "awayteam": parse_team(info["competitors"][1]),
            "time": info["status"]["displayClock"],
            "quarter": info["status"]["period"],
            "over": info["status"]["type"]["completed"],
            "detail": info["status"]["type"]["detail"],
            "halftime": info["status"]["type"]["name"],
            "state": info["status"]["type"]["state"],
        }
        games.append(game)
    return games

def get_next_game(cutoff_time,  timezone, team_id, next_game_day):
    res = http.get(SCOREBOARD_URL + "?dates=" + get_date_string(next_game_day))
    if res.status_code != 200:
        print("Error fetching game data")
        return []
    
    data = json.decode(res.body())
    for event in data["events"]:
        info = event["competitions"][0]
        game = {
            "name": event["shortName"],
            "date": event["date"],
            "hometeam": parse_team(info["competitors"][0]),
            "awayteam": parse_team(info["competitors"][1]),
            "time": info["status"]["displayClock"],
            "quarter": info["status"]["period"],
            "over": info["status"]["type"]["completed"],
            "detail": info["status"]["type"]["detail"],
            "halftime": info["status"]["type"]["name"],
            "state": info["status"]["type"]["state"],
        }
        if game["hometeam"]["id"] == team_id or game["awayteam"]["id"] == team_id:
            return game
    return None

def get_next_game_date(team_id, cutoff_time, timezone):
    res = http.get(SCHEDULE_URL.replace("team_id", team_id))
    if res.status_code != 200:
        print("Error fetching game data")
        return []

    data = json.decode(res.body())

    now = get_cutoff_date(cutoff_time, timezone)

    next_game_day = None
    for event in data['events']:
        gamedatetime = time.parse_time(event["date"], format="2006-01-02T15:04Z")
        local_gamedatetime = gamedatetime.in_location(timezone)
        if local_gamedatetime == now:
            next_game_day = now
            break
        elif local_gamedatetime > now:
            next_game_day = local_gamedatetime
            break
    return next_game_day

def parse_team(team_data):
    logo_url = team_data["team"]["logo"] if "logo" in team_data["team"] else ""
    processed_logo = get_logoType(team_data["team"]["abbreviation"], logo_url)
    
    return {
        "teamName": team_data["team"]["abbreviation"],
        "id": team_data["id"],
        "score": parse_score(team_data.get("score", 0)),
        "color": team_data["team"]["color"],
        "altcolor": team_data["team"]["alternateColor"],
        "record": team_data["records"][0]["summary"] if "records" in team_data else None,
        "logo": processed_logo,
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

def get_cachable_data(url, ttl_seconds = CACHE_TTL_SECONDS):
    res = http.get(url = url, ttl_seconds = ttl_seconds)
    if res.status_code != 200:
        fail("request to %s failed with status code: %d - %s" % (url, res.status_code, res.body()))
    return res.body()

def render_game_indicator(game_count, index):
    children = []
    if game_count > 1:
        for i in range(game_count):
            color = RED if i == index else GREY
            children.append(render.Box(height=1, width=1, color=color))
            
            if i < game_count - 1:
                children.append(render.Box(height=1, width=2, color=BLACK))

    return render.Row(
        main_align="center",
        cross_align="end",
        expanded = True,
        children = children
    )

def render_team_column(team):
    return render.Column(
        expanded = True,
        main_align="space_evenly",
        cross_align="center",
        children = [
            render.Image(src = team["logo"], width = 20, height = 20),
            render.Text(content=team["teamName"], font="tom-thumb", color=WHITE)
        ]
    )

def render_game(game, now, timezone, game_count, index):
    return render.Stack(
        children = [
            render.Row(
                expanded = True,
                main_align="center",
                cross_align="center",
                children = [
                    render.Box(
                        width = 20,
                        height = 32,
                        child = render_team_column(game["awayteam"])
                    ),
                    render.Box(
                        width = 24,
                        height = 32,
                        child = render_game_status_column(game, now, timezone)
                    ),
                    render.Box(
                        width = 20,
                        height = 32,
                        child = render_team_column(game["hometeam"])
                    ),
                ]
            ),
            render.Column(
                main_align="end",
                cross_align="end",
                expanded = True,
                children = [
                    render_game_indicator(game_count, index),
                    #render a space
                    render.Row(
                        main_align="start",
                        cross_align="end",
                        expanded = True,
                        children = [render.Box(height=1, width=1, color=BLACK)]
                    ),
                ]
            )
        ]
    )  
    
def render_game_status_column(game, now, timezone):
    status = get_game_status(game, now, timezone)
    
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

    if status.get("score"):
        children.append(
            render.Box(height=1, color=BLACK)
        )
        children.append(
            render.Text(content=status["score"], font="6x13", color=WHITE)
        )
    
    if status.get("versus"):
        children.append(
            render.Box(height=1, color=BLACK)
        )
        children.append(
            render.Text(content=status["versus"], font="6x13", color=WHITE)
        )
    
    return render.Column(
        expanded=True,
        main_align="start",
        cross_align="center",
        children=children
    )


def get_game_status(game, now, timezone):
    gamedatetime = time.parse_time(game["date"], format="2006-01-02T15:04Z")
    local_gamedatetime = gamedatetime.in_location(timezone)

    home_score = game["hometeam"]["score"]
    away_score = game["awayteam"]["score"]
    concatenated_score = str(away_score) + "-" + str(home_score)
    
    if game["state"] == "pre":
        date_text = "TODAY" if local_gamedatetime.day == now.day else local_gamedatetime.format("Jan 2")
        gametime = local_gamedatetime.format("03:04")
        return {
            "date_text": date_text, 
            "gametime": gametime,
            "versus": "VS"
        }
    elif game["state"] == "post":
        date_text = local_gamedatetime.format("Jan 2")
        final_text = "Final" if game["detail"] != "Final/OT" else "F/OT"
        return {
            "date_text": date_text, 
            "final_text": final_text,
            "score": concatenated_score
        }
    else:
        time_text = "END" if game["time"] in ["0:00", "0:0", "0.00", "0.0"] else game["time"]
        return {
            "quarter": ORDINAL[game["quarter"]], 
            "time": time_text,
            "score": concatenated_score
        }

def get_cutoff_date(cutoff_hour, timezone):
    # Get the current time in the specified timezone
    now = time.now().in_location(timezone)

    # Check if the current hour is before the cutoff time
    if now.hour < cutoff_hour:
        # If before the cutoff time, return yesterday's date
        yesterday = now - time.parse_duration("24h")
        return time.time(year=yesterday.year, month=yesterday.month, day=yesterday.day, location=timezone)
    else:
        # If on or after the cutoff time, return today's date
        return time.time(year=now.year, month=now.month, day=now.day, location=timezone)

def get_date_string(date):
    year = date.year
    month = date.month
    day = date.day
    
    year_str = str(year)
    month_str = "0" + str(month) if month < 10 else str(month)
    day_str = "0" + str(day) if day < 10 else str(day)
    
    return year_str + month_str + day_str
    
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