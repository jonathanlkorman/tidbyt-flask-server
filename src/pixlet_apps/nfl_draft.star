load("encoding/json.star", "json")
load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

CACHE_TTL_SECONDS = 300

URL = "https://site.web.api.espn.com/apis/v2/scoreboard/header"

WHITE = "#FFFFFF"
BLACK = "#000000"
RED = "#FF0000"


DEFAULT_TIMEZONE = "America/New_York"
DEFAULT_TEAM = "Jets"

NFL_TEAM_COLORS = {
    "Cardinals": "#B01C3B",     
    "Falcons": "#C8102E",
    "Ravens": "#341A7F",
    "Bills": "#0044B7",
    "Panthers": "#00A3E0",
    "Bears": "#11243D",         
    "Bengals": "#FF652F",
    "Browns": "#4A2C00",
    "Cowboys": "#102A5E",
    "Broncos": "#163778",       
    "Lions": "#1491D2",         
    "Packers": "#2A4436",      
    "Texans": "#0D2A42",
    "Colts": "#0047BB",
    "Jaguars": "#008F99",
    "Chiefs": "#F01A37",
    "Raiders": "#1A1A1A",       
    "Chargers": "#003DA5",
    "Rams": "#0046B3",
    "Dolphins": "#00A6A6",
    "Vikings": "#5F35A3",
    "Patriots": "#003366",
    "Saints": "#E1C67A",        
    "Giants": "#1E3B9C",
    "Jets": "#168C63",         
    "Eagles": "#02636C",
    "Steelers": "#FFCD1C",
    "49ers": "#C8102E",
    "Seahawks": "#1C4F9C",
    "Buccaneers": "#E51919",
    "Titans": "#5CA7ED",
    "Commanders": "#7A1F1F"
}


def main(config):
    timezone = config.get("timezone", DEFAULT_TIMEZONE)
    now = time.now().in_location(timezone)
    
    preferred_team = config.get("preferred_team", DEFAULT_TEAM)
    
    draft_data = get_draft_data()
    
    if not draft_data:
        return render.Root(child = render.Text("No data available"))

    children = []
    children.append(
        render.Text(
            content = preferred_team,
            font = "CG-pixel-3x5-mono",
            color = NFL_TEAM_COLORS.get(preferred_team, WHITE),
        )
    )
    children.append(render.Box(width = 64, height = 1, color = BLACK))
    children.append(render.Box(width = 64, height = 1, color = NFL_TEAM_COLORS.get(preferred_team, WHITE)))

    for i, pick in enumerate(draft_data[preferred_team], 1):
        formatted_round_number = print_aligned_numbers(pick['overall_pick'])
        children.append(render.Box(width = 64, height = 2, color = BLACK))
        children.append(
            render.Row(
                expanded = True,
                main_align = "start",
                cross_align = "center",
                children = [
                    render.Text(content="{}".format(formatted_round_number), font="CG-pixel-3x5-mono", color= RED if pick['traded'] else WHITE),
                    render.Text(content="{} ".format(pick['position']), font="CG-pixel-3x5-mono", color=WHITE),
                    render.Text(content="{}".format(pick['player_name']), font="CG-pixel-3x5-mono", color=WHITE),
                ]
            )
        )

    
    return render.Root(child = render.Marquee(
        height = 32,
        delay = 50,
        offset_start=0,
        scroll_direction = "vertical",
        child = render.Column(
            expanded = False,
            main_align = "start",
            cross_align = "start",
            children = children
        )
    ))

def get_draft_data():
    res = http.get(URL)
    if res.status_code != 200:
        print("Error fetching data")
        return []
    
    data = json.decode(res.body())
    rounds = data["sports"][0]["leagues"][0]["draft"]["rounds"]

    teams_picks = dict()

    position_mapping = {
        "EDGE": "DE"
    }
    
    for round_data in rounds:
        round_number = round_data["number"]
        
        for pick_data in round_data["picks"]:
            team_name = pick_data["team"]

            position = pick_data["position"]
            mapped_position = position_mapping.get(position, position)
            
            pick_entry = {
                "round": round_number,
                "pick_in_round": pick_data["pick"],
                "overall_pick": pick_data["overall"],
                "player_name": pick_data["shortName"],
                "position": mapped_position,
                "college": pick_data["college"],
                "traded": pick_data["traded"],
                "trade_note": pick_data["note"] if pick_data["note"] else None
            }
            
            if team_name not in teams_picks:
                teams_picks[team_name] = []
            teams_picks[team_name].append(pick_entry)
    
    return teams_picks

def print_aligned_numbers(number):
    num_str = str(number)
    if len(num_str) == 1:
        padding = "  "
    elif len(num_str) == 2:
        padding = " "
    else:
        padding = ""
    
    return "{}{}".format(num_str, padding)

