#!/usr/bin/env bash

# ==========================================
# SCOUNDREL - Terminal Card Game
# ==========================================

# ANSI Color Codes
NC='\033[0m' # Reset
BOLD='\033[1m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'


# Game State Variables
HEALTH=20 # default 20
MAX_HEALTH=20 # default 20
MAX_CONSECUTIVE_ESCAPES=2 # default 1
LESS_THAN_OR_EQUAL=1 # Use the less than or equal rule for weapon use, else just Less Than
INVINCIBLE_START=0 # Set to 1 to start with an Invincible Weapon

CONSECUTIVE_ESCAPES=0
EQUIPPED_WEAPON_VAL=0
EQUIPPED_WEAPON_NAME=""
LAST_SLAIN_VAL=999 # Max value so any first monster can be fought with a new weapon

# equip a BFG9000 to start with
if [ $INVINCIBLE_START -eq 1 ]; then
    EQUIPPED_WEAPON_VAL=99
    EQUIPPED_WEAPON_NAME="BFG9000"
fi


POTION_USED_THIS_TURN=0

# Deck arrays
DUNGEON=()
ROOM=()
DISCARD=()

# Function to get card value
get_card_value() {
    local card=$1
    local rank="${card:0:-1}"
    case "$rank" in
        J) echo 11 ;;
        Q) echo 12 ;;
        K) echo 13 ;;
        A) echo 14 ;;
        *) echo "$rank" ;;
    esac
}

# Function to get card suit
get_card_suit() {
    local card=$1
    echo "${card: -1}"
}

# Function to format card for display with colored suits
format_card() {
    local card=$1
    local rank="${card:0:-1}"
    local suit="$(get_card_suit "$card")"
    
    case "$suit" in
        C) echo "${rank}♣ (Monster)" ;;
        S) echo "${rank}♠ (Monster)" ;;
        D) echo "${rank}${RED}♦${NC} (Weapon)" ;;
        H) echo "${rank}${RED}♥${NC} (Potion)" ;;
    esac
}

# Initialize Deck according to rules
init_deck() {
    local temp_deck=()
    
    # 26 Monsters: Clubs & Spades (2 through Ace)
    for suit in C S; do
        for rank in 2 3 4 5 6 7 8 9 10 J Q K A; do
            temp_deck+=("${rank}${suit}")
        done
    done
    
    # 9 Weapons: Diamonds (2 through 10)
    for rank in {2..10}; do
        temp_deck+=("${rank}D")
    done
    
    # 9 Potions: Hearts (2 through 10)
    for rank in {2..10}; do
        temp_deck+=("${rank}H")
    done

    # Shuffle the deck
    while [ ${#temp_deck[@]} -gt 0 ]; do
        local rand_idx=$(( RANDOM % ${#temp_deck[@]} ))
        DUNGEON+=("${temp_deck[$rand_idx]}")
        temp_deck=("${temp_deck[@]:0:$rand_idx}" "${temp_deck[@]:$((rand_idx + 1))}")
    done
}

# Draw cards into the Room until it has 4 cards or Dungeon is empty
refill_room() {
    while [ ${#ROOM[@]} -lt 4 ] && [ ${#DUNGEON[@]} -gt 0 ]; do
        ROOM+=("${DUNGEON[0]}")
        DUNGEON=("${DUNGEON[@]:1}")
    done
    # echo $(date +%H:%M:%S) Room:${#ROOM[@]}  Dungeon:${#DUNGEON[@]} >> scoundrel.log
}

# Helper to print a line with exact visual column padding (strips ANSI codes for length math)
print_box_line() {
    local text="$1"
    # Strip ANSI escape codes to measure true visual width
    local clean_text
    clean_text=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local char_count=${#clean_text}
    local pad_len=$(( 30 - char_count ))
    
    if [ $pad_len -lt 0 ]; then pad_len=0; fi
    
    printf "║ %b%*s ║\n" "$text" "$pad_len" ""
}

# Display helper to clear terminal and draw current UI frame using ANSI borders
render_ui() {
    clear
    local msg="$1"
    local faced_status="$2"

    echo "╔════════════════════════════════╗"
    print_box_line "           SCOUNDREL"
    echo "╠════════════════════════════════╣"
    
    # Health, Deck Left, Escapes
    local status_line
    status_line1=$(printf "Health: %-2d/%-2d  │ Deck Left: %-2d" \
        "$HEALTH" "$MAX_HEALTH" "${#DUNGEON[@]}" )
    status_line2=$(printf "Escapes Used: %d/%d" \
        "$CONSECUTIVE_ESCAPES" "$MAX_CONSECUTIVE_ESCAPES")
    print_box_line "$status_line1"
    print_box_line "$status_line2"
    
    # Weapon status
    if [ $EQUIPPED_WEAPON_VAL -gt 0 ]; then
        if [ $LAST_SLAIN_VAL -eq 999 ]; then
            local w_line
            w_line1=$(printf "Weapon: %b" "$EQUIPPED_WEAPON_NAME")
            w_line2=$(printf "        (Durability: Unused)" )
            print_box_line "$w_line1"
            print_box_line "$w_line2"
        else
            local w_line
	    if [ $LESS_THAN_OR_EQUAL -eq 1 ]; then
                w_line1=$(printf "Weapon: %b" "$EQUIPPED_WEAPON_NAME" )
                w_line2=$(printf "        (Can fight ≤ %d)" "$LAST_SLAIN_VAL")
	    else
                w_line1=$(printf "Weapon: %b" "$EQUIPPED_WEAPON_NAME" )
                w_line2=$(printf "        (Can fight < %d)" "$LAST_SLAIN_VAL")
	    fi
            print_box_line "$w_line1"
            print_box_line "$w_line2"
        fi
    else
        print_box_line "Weapon: None"
    fi
    echo "╟────────────────────────────────╢"
    
    # Room Cards Header
    print_box_line "Room Cards ($faced_status):"
    
    # Room Cards Listing
    for i in "${!ROOM[@]}"; do
        formatted="$(format_card "${ROOM[$i]}")"
        print_box_line "  $((i+1)). $formatted"
    done
    
    echo "╚════════════════════════════════╝"
    if [ -n "$msg" ]; then
        echo -e "$msg"
        echo "──────────────────────────────────"
    fi
}

# Initialize game
init_deck
LAST_FACED_CARD=""
ACTION_LOG=""

# Main Turn Loop
while true; do
    # Refill room up to 4 cards at the start of a turn
    refill_room

    # Check Win Condition
    if [ ${#ROOM[@]} -eq 0 ] && [ ${#DUNGEON[@]} -eq 0 ]; then
        clear
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║                                                          ║"
        echo -e "║                     ${BLUE}🎉${NC} VICTORY!                          ║"
        echo "║               You survived the dungeon!                  ║"
        echo "║                                                          ║"
        echo "╚══════════════════════════════════════════════════════════╝"
        SCORE=$HEALTH
        if [ "$HEALTH" -eq 20 ] && [ "${LAST_FACED_CARD: -1}" == "H" ]; then
            pot_val=$(get_card_value "$LAST_FACED_CARD")
            SCORE=$(( SCORE + pot_val ))
            echo "Bonus potion score applied!"
        fi
        echo "Final Score: $SCORE"
        exit 0
    fi

    POTION_USED_THIS_TURN=0

    # Player must face 3 cards in this room (or until 1 card remains)
    CARDS_FACED_THIS_TURN=0
    
    while ([ $CARDS_FACED_THIS_TURN -lt 3 ] && [ ${#ROOM[@]} -gt 1 ]) || ([ ${#DUNGEON[@]} -eq 0 ] && [ ${#ROOM[@]} -gt 0 ]); do
        # Determine if escape is available (only at start of room with 4 cards)
        can_escape=0
        if [ $CARDS_FACED_THIS_TURN -eq 0 ] && [ ${#ROOM[@]} -eq 4 ] && [ $CONSECUTIVE_ESCAPES -lt $MAX_CONSECUTIVE_ESCAPES ]; then
            can_escape=1
        fi

        render_ui "$ACTION_LOG" "${CARDS_FACED_THIS_TURN}/3 cards faced"

        if [ $can_escape -eq 1 ]; then
		read -p "Face card(1-${#ROOM[@]}) or (e)scape: " choiceX
        else
            read -p "Face card(1-${#ROOM[@]}): " choiceX
        fi

	choice=${choiceX:0:1}
	choice2=${choiceX:1:1}

        # Check for Escape selection
        if [ $can_escape -eq 1 ] && [[ "$choice" == "e" || "$choice" == "E" ]]; then
            DUNGEON+=("${ROOM[@]}")
            ROOM=()
            CONSECUTIVE_ESCAPES=$((CONSECUTIVE_ESCAPES + 1))
            ACTION_LOG="You escaped the room!\nCards replaced in dungeon."
            break # Break out of inner turn loop to refill room and restart turn
        fi

        # Validate input for card selection
        if ! [[ "$choice" =~ ^[1-9]$ ]] || [ "$choice" -gt "${#ROOM[@]}" ]; then
            ACTION_LOG="Invalid selection."
            continue
        fi

        # Valid card chosen: Reset consecutive escapes
        CONSECUTIVE_ESCAPES=0

        idx=$((choice - 1))
        card="${ROOM[$idx]}"
        ROOM=("${ROOM[@]:0:$idx}" "${ROOM[@]:$((idx + 1))}")
        CARDS_FACED_THIS_TURN=$((CARDS_FACED_THIS_TURN + 1))
        LAST_FACED_CARD="$card"

        val=$(get_card_value "$card")
        suit=$(get_card_suit "$card")

        case "$suit" in
            D) # Weapon Card
                EQUIPPED_WEAPON_VAL=$val
                EQUIPPED_WEAPON_NAME="$(format_card "$card")"
                LAST_SLAIN_VAL=999
                ACTION_LOG="Picked up $(format_card "$card")"
                ;;
            H) # Health Potion Card
                if [ $POTION_USED_THIS_TURN -eq 0 ]; then
                    HEALTH=$(( HEALTH + val ))
                    if [ $HEALTH -gt $MAX_HEALTH ]; then
                        HEALTH=$MAX_HEALTH
                    fi
                    POTION_USED_THIS_TURN=1
                    # ACTION_LOG=">>> You drank $(format_card "$card") and restored health! (Current HP: $HEALTH)"
                    ACTION_LOG=">>> You drank $(format_card "$card"). "
                else
                    ACTION_LOG=">>> Already drunk this turn. $(format_card "$card") discarded!"
                fi
                ;;
            C|S) # Monster Card
                can_use_weapon=0
		LAST_SLAIN_VAL2=$LAST_SLAIN_VAL
		if [ $LESS_THAN_OR_EQUAL -eq 0 ]; then
			((LAST_SLAIN_VAL2--))
		fi

                if [ $EQUIPPED_WEAPON_VAL -gt 0 ] && [ $val -le $LAST_SLAIN_VAL2 ]; then
                    can_use_weapon=1
                fi

                if [ $can_use_weapon -eq 1 ]; then
                    while true; do
                        render_ui ">>> Monster encountered: $(format_card "$card") (Damage Value: $val)" "${CARDS_FACED_THIS_TURN}/3 cards faced"
                        echo "Combat Options:"
                        echo -e "  [b] Fight barehanded (Take full $val damage)"
                        echo -e "  [w] Fight using weapon $EQUIPPED_WEAPON_NAME"
			if [[ "$choice2" == "w" || "$choice2" == "W" || "$choice2" == "B" || "$choice2" == "b" ]]; then
				c_opt=$choice2
			else
                                read -p "Choose combat option (b/w): " c_opt
			fi


                        if [[ "$c_opt" == "w" || "$c_opt" == "W" ]]; then
                            dmg=$(( val - EQUIPPED_WEAPON_VAL ))
                            if [ $dmg -lt 0 ]; then dmg=0; fi
                            HEALTH=$(( HEALTH - dmg ))
                            LAST_SLAIN_VAL=$val
                            # ACTION_LOG=">>> You attacked $(format_card "$card") with $EQUIPPED_WEAPON_NAME!\nTook $dmg dmg. Monster value ($val) sets next weapon limit."
			    ACTION_LOG="Fight $(format_card "$card") - $EQUIPPED_WEAPON_NAME\nTook $dmg dmg. New wpn limit $val."
                            break
                        elif [[ "$c_opt" == "b" || "$c_opt" == "B" ]]; then
                            HEALTH=$(( HEALTH - val ))
                            ACTION_LOG="Fight $(format_card "$card") barehanded\nTook $val damage!"
                            break
                        else
                            ACTION_LOG="Invalid combat option."
                        fi
                    done
                else
                    note=""
                    if [ $EQUIPPED_WEAPON_VAL -gt 0 ]; then
                        note="\n(Weapon not used. Monster $val > $LAST_SLAIN_VAL)"
			if [ $LESS_THAN_OR_EQUAL -eq 0 ]; then
                            note="\n(Weapon not used. Monster $val ≥ $LAST_SLAIN_VAL)"
			fi
                    fi
                    HEALTH=$(( HEALTH - val ))
                    ACTION_LOG="Fought $(format_card "$card") barehanded \ntook $val damage!$note"
                fi
                ;;
        esac

        # Check Loss Condition
        if [ $HEALTH -le 0 ]; then
            clear
            echo "╔══════════════════════════════════════════════════════════╗"
            echo "║                                                          ║"
            echo -e "║          ${RED}💀${NC} GAME OVER! You died in the dungeon.          ║"
            echo "║                                                          ║"
            echo "╚══════════════════════════════════════════════════════════╝"
            
            REMAINING_MONSTER_SUM=0
            ALL_REMAINING=("${DUNGEON[@]}" "${ROOM[@]}")
            for c in "${ALL_REMAINING[@]}"; do
                s=$(get_card_suit "$c")
                if [ "$s" == "C" ] || [ "$s" == "S" ]; then
                    v=$(get_card_value "$c")
                    REMAINING_MONSTER_SUM=$(( REMAINING_MONSTER_SUM + v ))
                fi
            done
            
            echo "Final Score: -$REMAINING_MONSTER_SUM"
            exit 0
        fi
    done
done
