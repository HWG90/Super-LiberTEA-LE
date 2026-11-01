-- UI colors and readable key labels.
local M={}
M.palette={background={17,22,27},panel={23,29,35},header={31,38,44},
    border={65,77,85},line={43,53,61},white={231,236,239},muted={153,166,175},
    brass={221,184,105},focus={119,185,205},hover={35,46,55},selected={38,53,63},
    field={29,39,47},field_hover={40,55,65},enabled={118,207,177},disabled={111,124,133}}
-- Epic LUT's neutral workspace skin. Keep the original palette available to
-- integrations that use it; the MCM workspace uses this skin by default.
M.workspace={background={12,14,16},panel={19,21,23},header={25,27,29},
    border={62,66,69},border_hover={106,111,114},line={34,37,40},
    white={234,235,228},muted={154,159,159},brass={221,184,105},focus={244,202,53},
    hover={29,31,33},selected={43,39,24},text_selection={48,117,158},
    field={29,31,34},field_hover={39,42,45},enabled={176,205,176},disabled={105,111,113},
    nav_mod={29,32,34},nav_page={23,26,28},nav_border={62,68,71},
    nav_text={218,222,219},nav_branch={120,128,130}}
function M.text_size(size,role,scale)
    role=role or ((size or 20)>=28 and 'title' or (size or 20)>=22 and 'heading' or (size or 20)<=16 and 'hint' or 'body')
    local ratio=role=='heading'and 1.15 or role=='title'and 1.5 or role=='hint'and .88 or 1
    return 20*(scale or 1)*ratio,role
end
local key_names={[1]='Mouse 1',[2]='Mouse 2',[4]='Mouse 3',[5]='Mouse 4',[6]='Mouse 5',[256]='MWheel Up',[257]='MWheel Down',
    [8]='Backspace',[9]='Tab',[12]='Clear',[13]='Enter',[16]='Shift',[17]='Ctrl',[18]='Alt',[19]='Pause',[20]='Caps Lock',[27]='Esc',[32]='Space',
    [33]='Page Up',[34]='Page Down',[35]='End',[36]='Home',[37]='Left',[38]='Up',[39]='Right',[40]='Down',[44]='Print Screen',[45]='Insert',[46]='Del',
    [91]='Left Win',[92]='Right Win',[93]='Menu',[106]='Num *',[107]='Num +',[109]='Num -',[110]='Num .',[111]='Num /',
    [144]='Num Lock',[145]='Scroll Lock',[160]='Left Shift',[161]='Right Shift',[162]='Left Ctrl',[163]='Right Ctrl',[164]='Left Alt',[165]='Right Alt',
    [186]=';',[187]='=',[188]=',',[189]='-',[190]='.',[191]='/',[192]='`',[219]='[',[220]='\\',[221]=']',[222]="'",[223]='OEM 8',[226]='OEM 102'}
function M.key_name(code)
    if code==0 then return 'Not bound'end
    if key_names[code]then return key_names[code]end
    if code>=48 and code<=90 then return string.char(code)end
    if code>=112 and code<=135 then return 'F'..tostring(code-111)end
    if code>=96 and code<=105 then return 'Num '..tostring(code-96)end
    return 'VK '..tostring(code)
end

return M
