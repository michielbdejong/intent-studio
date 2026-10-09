port module Main exposing (Msg(..), Node(..), Operation(..), apply, applyChange, changeDecoder, documentAt, encodeHistory, encodeNode, find, init, main, root, seedHistory, strokeCount, update)

import Browser
import Browser.Events
import Html exposing (Html, button, div, h1, h2, input, p, span, text, textarea)
import Html.Attributes as A
import Html.Events as E
import Json.Decode as D
import Json.Encode as J
import Set exposing (Set)
import Svg exposing (Svg)
import Svg.Attributes as S
import Time


port save : J.Value -> Cmd msg


port regenerate : J.Value -> Cmd msg


port regenerated : (J.Value -> msg) -> Sub msg


port download : J.Value -> Cmd msg



-- All document mutations are serializable operations. UI state is separate.


type Node
    = Node { id : String, title : String, prompt : String, hidden : Bool, children : List Node, stroke : Maybe Stroke }


type alias Stroke =
    { x1 : Float, y1 : Float, x2 : Float, y2 : Float, color : String, width : Float }


type Operation
    = Add String Node
    | Move String String Int
    | Translate String Float Float
    | Visibility String Bool
    | Revise String String
    | Replace String Node


type alias Change =
    { title : String, why : String, intent : String, operations : List Operation }


type alias Model =
    { history : List Change, cursor : Int, selected : String, collapsed : Set String, expandedHistory : Set Int, dragged : Maybe String, playing : Bool, draft : String, notice : String, pending : Maybe Pending, generationError : Maybe String, requestCounter : Int }


type alias Pending =
    { id : Int, revision : Int, intent : String, prompt : String }


type alias Generated =
    { requestId : Int, revision : Int, node : Node, explanation : String, model : String }


type Msg
    = Select String
    | Collapse String
    | HistoryToggle Int
    | Seek String
    | Play
    | Tick Time.Posix
    | Drag String
    | DragEnd
    | Drop String Bool
    | Reorder Int
    | Nudge Float Float
    | Hide
    | Edit String
    | SaveIntent
    | Redraw
    | GeneratedResult J.Value
    | Export
    | ExportSvg
    | Reset


main : Program J.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions =
            \m ->
                Sub.batch
                    [ regenerated GeneratedResult
                    , Browser.Events.onMouseUp (D.succeed DragEnd)
                    , if m.playing then
                        Time.every 650 Tick

                      else
                        Sub.none
                    ]
        }


init : J.Value -> ( Model, Cmd Msg )
init flags =
    let
        restored =
            D.decodeValue (D.field "history" (D.list changeDecoder)) flags

        history =
            Result.withDefault seedHistory restored

        note =
            case restored of
                Ok _ ->
                    "Restored your saved session"

                Err _ ->
                    "A drawing with a memory"
    in
    ( { history = history, cursor = List.length history, selected = "tower", collapsed = Set.fromList [ "leg-left", "leg-right", "spire", "platforms", "braces-left", "braces-right", "banks", "ripples", "boat", "clouds" ], expandedHistory = Set.empty, dragged = Nothing, playing = False, draft = find "tower" (List.foldl applyChange root history) |> Maybe.map (\(Node n) -> n.prompt) |> Maybe.withDefault "", notice = note, pending = Nothing, generationError = Nothing, requestCounter = 0 }, Cmd.none )


node : String -> String -> String -> List Node -> Node
node id title prompt children =
    Node { id = id, title = title, prompt = prompt, hidden = False, children = children, stroke = Nothing }


root : Node
root =
    node "scene" "Paris postcard" "Draw a postcard of Paris, with the Eiffel Tower on the left and the Seine in the foreground." []


nodeId : Node -> String
nodeId (Node n) =
    n.id


find : String -> Node -> Maybe Node
find id ((Node n) as current) =
    if n.id == id then
        Just current

    else
        List.filterMap (find id) n.children |> List.head


modify : String -> (Node -> Node) -> Node -> Node
modify id fn ((Node n) as current) =
    if n.id == id then
        fn current

    else
        Node { n | children = List.map (modify id fn) n.children }


remove : String -> Node -> Node
remove id (Node n) =
    Node { n | children = List.filter (\child -> nodeId child /= id) n.children |> List.map (remove id) }


insertAt : Int -> a -> List a -> List a
insertAt index value xs =
    List.take index xs ++ [ value ] ++ List.drop index xs


shift : Float -> Float -> Node -> Node
shift dx dy (Node n) =
    Node { n | children = List.map (shift dx dy) n.children, stroke = Maybe.map (\s -> { s | x1 = s.x1 + dx, x2 = s.x2 + dx, y1 = s.y1 + dy, y2 = s.y2 + dy }) n.stroke }


apply : Operation -> Node -> Node
apply operation document =
    case operation of
        Add parent child ->
            modify parent (\(Node n) -> Node { n | children = n.children ++ [ child ] }) document

        Move id parent index ->
            case ( find id document, find parent document ) of
                ( Just subtree, Just _ ) ->
                    if id == "scene" || find parent subtree /= Nothing then
                        document

                    else
                        modify parent (\(Node n) -> Node { n | children = insertAt index subtree n.children }) (remove id document)

                _ ->
                    document

        Translate id dx dy ->
            modify id (shift dx dy) document

        Visibility id hidden ->
            modify id (\(Node n) -> Node { n | hidden = hidden }) document

        Replace id replacement ->
            if nodeId replacement == id then
                modify id (\_ -> replacement) document

            else
                document

        Revise id prompt ->
            modify id (\(Node n) -> Node { n | prompt = prompt }) document


applyChange : Change -> Node -> Node
applyChange change document =
    List.foldl apply document change.operations


documentAt : Model -> Node
documentAt model =
    List.foldl applyChange root (List.take model.cursor model.history)


parentOf : String -> Node -> Maybe Node
parentOf id ((Node n) as current) =
    if List.any (\child -> nodeId child == id) n.children then
        Just current

    else
        List.filterMap (parentOf id) n.children |> List.head


indexOf : String -> List Node -> Int
indexOf id children =
    List.indexedMap Tuple.pair children |> List.filter (\( _, child ) -> nodeId child == id) |> List.head |> Maybe.map Tuple.first |> Maybe.withDefault 0


commit : Change -> Model -> ( Model, Cmd Msg )
commit change model =
    if model.pending /= Nothing then
        ( { model | notice = "Wait for regeneration to finish before changing the drawing." }, Cmd.none )

    else if model.cursor /= List.length model.history then
        ( { model | notice = "Return to Latest before editing. History stays intact." }, Cmd.none )

    else
        let
            history =
                model.history ++ [ change ]
        in
        ( { model | history = history, cursor = List.length history, playing = False, dragged = Nothing, notice = change.title ++ " · saved locally" }, save (encodeHistory history) )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        doc =
            documentAt model
    in
    case msg of
        Select id ->
            let
                prompt =
                    find id doc |> Maybe.map (\(Node n) -> n.prompt) |> Maybe.withDefault ""
            in
            ( { model | selected = id, draft = prompt, generationError = Nothing }, Cmd.none )

        Collapse id ->
            ( { model | collapsed = toggle id model.collapsed }, Cmd.none )

        HistoryToggle index ->
            ( { model | expandedHistory = toggle index model.expandedHistory }, Cmd.none )

        Seek value ->
            ( { model | cursor = clamp 0 (List.length model.history) (String.toInt value |> Maybe.withDefault model.cursor), playing = False }, Cmd.none )

        Play ->
            ( { model
                | playing = not model.playing
                , cursor =
                    if model.cursor == List.length model.history then
                        0

                    else
                        model.cursor
              }
            , Cmd.none
            )

        Tick _ ->
            ( { model | cursor = min (model.cursor + 1) (List.length model.history), playing = model.cursor + 1 < List.length model.history }, Cmd.none )

        Drag id ->
            ( { model | dragged = Just id }, Cmd.none )

        DragEnd ->
            ( { model | dragged = Nothing }, Cmd.none )

        Drop target inside ->
            case model.dragged of
                Nothing ->
                    ( model, Cmd.none )

                Just id ->
                    let
                        destination =
                            if inside then
                                find target doc

                            else
                                parentOf target doc

                        subtree =
                            find id doc
                    in
                    case ( destination, subtree ) of
                        ( Just (Node dest), Just source ) ->
                            if find dest.id source /= Nothing || id == "scene" || id == target then
                                ( { model | dragged = Nothing, notice = "A branch cannot be moved inside itself." }, Cmd.none )

                            else if dest.stroke /= Nothing then
                                ( { model | dragged = Nothing, notice = "Drop inside an intent branch, not a stroke." }, Cmd.none )

                            else
                                let
                                    remaining =
                                        List.filter (\child -> nodeId child /= id) dest.children

                                    position =
                                        if inside then
                                            List.length remaining

                                        else
                                            indexOf target remaining
                                in
                                commit
                                    { title = "Rearrange " ++ titleOf id doc
                                    , why =
                                        if inside then
                                            "Move this work into “" ++ dest.title ++ "”. Geometry is preserved; its purpose may need revising."

                                        else
                                            "Change drawing order by moving this chunk before “" ++ titleOf target doc ++ "”."
                                    , intent = id
                                    , operations = [ Move id dest.id position ]
                                    }
                                    model

                        _ ->
                            ( { model | dragged = Nothing }, Cmd.none )

        Reorder direction ->
            case parentOf model.selected doc of
                Nothing ->
                    ( model, Cmd.none )

                Just (Node parent) ->
                    let
                        old =
                            indexOf model.selected parent.children

                        target =
                            clamp 0 (List.length parent.children - 1) (old + direction)
                    in
                    if old == target then
                        ( model, Cmd.none )

                    else
                        commit { title = "Reorder " ++ titleOf model.selected doc, why = "Move the entire chunk in the paint sequence. Later siblings paint on top of earlier siblings.", intent = model.selected, operations = [ Move model.selected parent.id target ] } model

        Nudge dx dy ->
            commit { title = "Move " ++ titleOf model.selected doc, why = "Translate this intention’s strokes together by (" ++ String.fromFloat dx ++ ", " ++ String.fromFloat dy ++ ") without changing their grouping.", intent = model.selected, operations = [ Translate model.selected dx dy ] } model

        Hide ->
            case find model.selected doc of
                Just (Node n) ->
                    commit
                        { title =
                            (if n.hidden then
                                "Show "

                             else
                                "Hide "
                            )
                                ++ n.title
                        , why = "Change visibility of this whole chunk, retaining all strokes and their intentions."
                        , intent = n.id
                        , operations = [ Visibility n.id (not n.hidden) ]
                        }
                        model

                Nothing ->
                    ( model, Cmd.none )

        Edit value ->
            ( { model | draft = value }, Cmd.none )

        Redraw ->
            case find model.selected doc of
                Just (Node n) ->
                    update SaveIntent { model | draft = n.prompt }

                Nothing ->
                    ( model, Cmd.none )

        SaveIntent ->
            if model.pending /= Nothing || model.cursor /= List.length model.history then
                ( model, Cmd.none )

            else if String.isEmpty (String.trim model.draft) then
                ( { model | generationError = Just "An intention needs some text." }, Cmd.none )

            else
                case find model.selected doc of
                    Nothing ->
                        ( model, Cmd.none )

                    Just subtree ->
                        let
                            request =
                                { id = model.requestCounter + 1, revision = List.length model.history, intent = model.selected, prompt = model.draft }
                        in
                        ( { model | pending = Just request, requestCounter = request.id, generationError = Nothing, playing = False, notice = "Redrawing this intention and all its children…" }
                        , regenerate (J.object [ ( "requestId", J.int request.id ), ( "revision", J.int request.revision ), ( "prompt", J.string request.prompt ), ( "subtree", encodeNode subtree ), ( "document", encodeNode doc ) ])
                        )

        GeneratedResult value ->
            case model.pending of
                Nothing ->
                    ( model, Cmd.none )

                Just request ->
                    if D.decodeValue (D.field "requestId" D.int) value /= Ok request.id then
                        ( model, Cmd.none )

                    else
                        case D.decodeValue generatedDecoder value of
                            Err _ ->
                                let
                                    message =
                                        D.decodeValue (D.field "error" D.string) value |> Result.withDefault "The model response could not be read. Your drawing has not changed."
                                in
                                ( { model | pending = Nothing, generationError = Just message, notice = "Regeneration failed. Your previous drawing is intact." }, Cmd.none )

                            Ok result ->
                                if result.revision /= request.revision || List.length model.history /= request.revision || model.cursor /= request.revision || nodeId result.node /= request.intent then
                                    ( { model | pending = Nothing, generationError = Just "The document or history position changed. Return to Latest and try again.", notice = "Discarded a stale model response." }, Cmd.none )

                                else
                                    let
                                        cleared =
                                            { model | pending = Nothing, generationError = Nothing, selected = request.intent, draft = request.prompt, collapsed = Set.remove request.intent model.collapsed }
                                    in
                                    commit { title = "Redraw " ++ titleOf request.intent doc, why = result.explanation ++ " · Generated by " ++ result.model, intent = request.intent, operations = [ Replace request.intent result.node ] } cleared

        Export ->
            ( model, download (J.object [ ( "kind", J.string "json" ), ( "data", encodeHistory model.history ) ]) )

        ExportSvg ->
            ( model, download (J.object [ ( "kind", J.string "svg" ) ]) )

        Reset ->
            let
                ( fresh, _ ) =
                    init J.null
            in
            ( { fresh | notice = "Started a fresh Paris postcard" }, save (encodeHistory fresh.history) )


toggle : comparable -> Set comparable -> Set comparable
toggle value set =
    if Set.member value set then
        Set.remove value set

    else
        Set.insert value set


titleOf : String -> Node -> String
titleOf id doc =
    find id doc |> Maybe.map (\(Node n) -> n.title) |> Maybe.withDefault id


strokeCount : Node -> Int
strokeCount (Node n) =
    (if n.stroke == Nothing then
        0

     else
        1
    )
        + List.sum (List.map strokeCount n.children)



-- The seed is itself a sequence of intention-bearing changes.


line : Float -> Float -> Float -> Float -> Stroke
line x1 y1 x2 y2 =
    { x1 = x1, y1 = y1, x2 = x2, y2 = y2, color = "#344a49", width = 2 }


withColor : String -> Float -> Stroke -> Stroke
withColor color width s =
    { s | color = color, width = width }


chunk : String -> String -> String -> List Stroke -> Node
chunk id title prompt strokes =
    node id title prompt (List.indexedMap (\index s -> Node { id = id ++ "-" ++ String.fromInt index, title = "Stroke " ++ String.fromInt (index + 1), prompt = "Draw this line to contribute to “" ++ title ++ "”.", hidden = False, children = [], stroke = Just s }) strokes)


polyline : List ( Float, Float ) -> List Stroke
polyline points =
    case points of
        ( x1, y1 ) :: (( x2, y2 ) :: _) ->
            line x1 y1 x2 y2 :: polyline (List.drop 1 points)

        _ ->
            []


seedHistory : List Change
seedHistory =
    [ { title = "Compose a Paris postcard", why = "Place a recognizable tower above the river, with open sky and room for a small boat.", intent = "scene", operations = [ Add "scene" (node "sky" "Open sky" "Keep the sky light, with a few delicate clouds." []), Add "scene" (node "tower" "Eiffel Tower" "Draw the Eiffel Tower on the left, with a recognizable iron silhouette." []), Add "scene" (node "river" "The Seine" "Draw the Seine across the foreground." []) ] }
    , { title = "Sketch a little atmosphere", why = "A few short cloud contours suggest a wide, calm sky.", intent = "sky", operations = [ Add "sky" (chunk "clouds" "Cloud contours" "Draw airy cloud outlines without filling the sky." (List.concat [ polyline [ ( 420, 135 ), ( 437, 135 ), ( 443, 127 ), ( 457, 124 ), ( 470, 129 ), ( 475, 135 ), ( 497, 135 ) ], polyline [ ( 92, 195 ), ( 107, 195 ), ( 114, 186 ), ( 126, 184 ), ( 137, 190 ), ( 145, 192 ), ( 159, 192 ) ], polyline [ ( 490, 226 ), ( 502, 225 ), ( 509, 219 ), ( 519, 220 ), ( 525, 226 ), ( 542, 226 ) ] ] |> List.map (withColor "#b9c7c4" 1.5))) ] }
    , { title = "Build the tower silhouette", why = "The splayed legs, tapered body and tall spire carry the tower’s identity before any detail is added.", intent = "tower", operations = [ Add "tower" (node "silhouette" "Silhouette" "Establish the tower’s recognizable outline." [ chunk "leg-left" "Left supporting leg" "Draw the left leg splaying outward toward its foot." (List.concat [ polyline [ ( 294, 235 ), ( 279, 305 ), ( 253, 370 ), ( 217, 445 ), ( 244, 445 ), ( 268, 394 ), ( 286, 365 ) ], polyline [ ( 298, 247 ), ( 290, 305 ), ( 276, 355 ) ], polyline [ ( 217, 445 ), ( 211, 450 ), ( 250, 450 ), ( 244, 445 ) ] ]), chunk "leg-right" "Right supporting leg" "Mirror the structure with a splayed right leg." (List.concat [ polyline [ ( 308, 235 ), ( 324, 305 ), ( 350, 370 ), ( 386, 445 ), ( 359, 445 ), ( 334, 394 ), ( 315, 365 ) ], polyline [ ( 304, 247 ), ( 313, 305 ), ( 327, 355 ) ], polyline [ ( 359, 445 ), ( 353, 450 ), ( 392, 450 ), ( 386, 445 ) ] ]), chunk "spire" "Upper spire" "Taper the upper tower into a slender antenna." (List.concat [ polyline [ ( 279, 305 ), ( 290, 223 ), ( 297, 173 ), ( 299, 137 ), ( 304, 137 ), ( 306, 173 ), ( 313, 223 ), ( 324, 305 ) ], polyline [ ( 301, 137 ), ( 301, 112 ) ], polyline [ ( 295, 173 ), ( 307, 173 ) ], polyline [ ( 291, 222 ), ( 312, 222 ) ] ]), chunk "platforms" "Platforms & arch" "Add the observation decks and the arch between the legs." (List.concat [ polyline [ ( 274, 303 ), ( 328, 303 ), ( 330, 311 ), ( 272, 311 ), ( 274, 303 ) ], polyline [ ( 251, 365 ), ( 351, 365 ), ( 354, 375 ), ( 248, 375 ), ( 251, 365 ) ], polyline [ ( 251, 426 ), ( 260, 407 ), ( 274, 394 ), ( 286, 387 ), ( 301, 384 ), ( 316, 387 ), ( 330, 394 ), ( 344, 407 ), ( 354, 426 ) ] ]) ]) ] }
    , { title = "Weave the iron lattice"
      , why = "Repeated diagonal braces make the legs read as an open iron structure instead of solid columns."
      , intent = "tower"
      , operations =
            [ Add "tower"
                (node "lattice"
                    "Iron latticework"
                    "Fill the legs with a rhythm of diagonal iron braces."
                    [ chunk "braces-left"
                        "Left-leg braces"
                        "Cross-brace the left supporting leg."
                        (List.range 0 6
                            |> List.concatMap
                                (\i ->
                                    let
                                        y =
                                            320 + toFloat i * 17

                                        x =
                                            278 - toFloat i * 7
                                    in
                                    [ line x y (x + 13) (y + 16), line (x + 13) y (x - 6) (y + 16) ]
                                )
                            |> List.map (withColor "#66817a" 1.1)
                        )
                    , chunk "braces-right"
                        "Right-leg braces"
                        "Cross-brace the right supporting leg."
                        (List.range 0 6
                            |> List.concatMap
                                (\i ->
                                    let
                                        y =
                                            320 + toFloat i * 17

                                        x =
                                            311 + toFloat i * 7
                                    in
                                    [ line x y (x + 19) (y + 16), line (x + 13) y (x + 6) (y + 16) ]
                                )
                            |> List.map (withColor "#66817a" 1.1)
                        )
                    ]
                )
            ]
      }
    , { title = "Let the river cross the foreground"
      , why = "Long riverbanks and broken horizontal strokes establish depth below the tower."
      , intent = "river"
      , operations =
            [ Add "river" (chunk "banks" "Riverbanks" "Sweep the banks across the lower part of the scene." (List.concat [ polyline [ ( 45, 480 ), ( 132, 471 ), ( 218, 474 ), ( 314, 465 ), ( 406, 470 ), ( 494, 457 ), ( 573, 464 ) ], polyline [ ( 42, 490 ), ( 133, 484 ), ( 219, 486 ), ( 315, 478 ), ( 406, 481 ), ( 496, 471 ), ( 573, 477 ) ] ] |> List.map (withColor "#749b9e" 1.8)))
            , Add "river"
                (chunk "ripples"
                    "Water ripples"
                    "Draw quiet, interrupted horizontal lines on the water."
                    (List.range 0 24
                        |> List.map
                            (\i ->
                                let
                                    x =
                                        54 + toFloat (modBy 7 (i * 3)) * 71

                                    y =
                                        508 + toFloat (i // 7) * 21 + toFloat (modBy 3 i) * 4
                                in
                                withColor "#9bb7b7" 1.4 (line x y (x + 20 + toFloat (modBy 4 i) * 9) y)
                            )
                    )
                )
            ]
      }
    , { title = "Add a boat for scale", why = "A small boat gives the river a focal point and makes the tower feel monumental.", intent = "river", operations = [ Add "river" (chunk "boat" "Little riverboat" "Draw a small riverboat on the right." (List.concat [ polyline [ ( 426, 518 ), ( 484, 518 ), ( 474, 529 ), ( 439, 529 ), ( 426, 518 ) ], polyline [ ( 438, 518 ), ( 442, 503 ), ( 467, 503 ), ( 472, 518 ) ], polyline [ ( 453, 503 ), ( 453, 494 ) ], polyline [ ( 445, 509 ), ( 449, 509 ) ], polyline [ ( 457, 509 ), ( 461, 509 ) ] ] |> List.map (withColor "#b57b52" 2))) ] }
    ]



-- View: current intent tree, SVG projection and chronological changes.


view : Model -> Html Msg
view model =
    let
        doc =
            documentAt model

        latest =
            model.cursor == List.length model.history && model.pending == Nothing
    in
    div
        [ A.class
            ("app"
                ++ (if model.dragged /= Nothing then
                        " dragging"

                    else
                        ""
                   )
            )
        ]
        [ Html.header [ A.class "topbar" ] [ div [ A.class "brand" ] [ span [ A.class "brand-icon" ] [ text "⌘" ], div [] [ h1 [] [ text "Intent Studio" ], span [ A.class "brand-sub" ] [ text "Every stroke has a story." ] ] ], div [ A.class "top-actions" ] [ span [ A.class "elm-badge" ] [ text "BUILT WITH ELM" ], button [ E.onClick Export, A.class "quiet" ] [ text "Export history ↗" ], button [ E.onClick ExportSvg, A.class "primary" ] [ text "Save drawing ↓" ] ] ]
        , div [ A.class "workspace-heading" ]
            [ div [] [ span [ A.class "eyebrow" ] [ text "A STUDY IN INTENTION / 001" ], h2 [] [ text "A postcard from Paris" ] ]
            , span [ A.class "session-badge" ]
                [ text
                    (if model.pending /= Nothing then
                        "◌  Redrawing"

                     else if latest then
                        "●  Live document"

                     else
                        "◷  Viewing the past"
                    )
                ]
            ]
        , div [ A.class "workspace" ]
            [ Html.aside [ A.class "panel tree-panel" ] [ panelHead "01" "Intent tree" (String.fromInt (strokeCount doc) ++ " strokes"), p [ A.class "panel-hint" ] [ text "Drag by the grip. Drop on a name to reorder, or on ↳ to move inside." ], div [ A.class "tree", A.attribute "aria-label" "Intent tree" ] [ treeView model doc 0 doc ], div [ A.class "tree-footer" ] [ span [] [ text "↓ Later siblings paint on top" ], span [] [ text "Purpose → parts → strokes" ] ] ]
            , div [ A.class "canvas-panel" ] [ div [ A.class "canvas-toolbar" ] [ span [] [ text "POSTCARD / PARIS" ], span [] [ text "SVG · 620 × 640" ] ], canvas model doc, div [ A.class "canvas-caption" ] [ span [] [ text "PARIS, EN QUELQUES TRAITS" ], span [] [ text "48°51′29.6″N  2°17′40.2″E" ] ], inspector model doc latest ]
            , Html.aside [ A.class "panel history-panel" ]
                [ panelHead "02" "History" (String.fromInt model.cursor ++ " / " ++ String.fromInt (List.length model.history))
                , p [ A.class "panel-hint" ] [ text "What happened, and why. Expand a change to see its operations." ]
                , div [ A.class "history-list" ] (List.indexedMap (historyView model) model.history)
                , div [ A.class "replay" ]
                    [ div [ A.class "replay-heading" ] [ span [] [ text "TIME TRAVEL" ], button [ E.onClick (Seek (String.fromInt (List.length model.history))), A.class "text-button" ] [ text "Latest ↗" ] ]
                    , input [ A.type_ "range", A.min "0", A.max (String.fromInt (List.length model.history)), A.value (String.fromInt model.cursor), E.onInput Seek, A.attribute "aria-label" "History position" ] []
                    , div [ A.class "replay-controls" ]
                        [ button [ E.onClick Play, A.class "quiet" ]
                            [ text
                                (if model.playing then
                                    "Ⅱ Pause"

                                 else
                                    "▷ Replay"
                                )
                            ]
                        , span [] [ text (String.fromInt model.cursor ++ " of " ++ String.fromInt (List.length model.history) ++ " changes") ]
                        ]
                    ]
                ]
            ]
        , Html.footer [ A.class "footer" ] [ span [ A.attribute "role" "status" ] [ text model.notice ], span [] [ text "Browser-local save · AI subtree regeneration" ] ]
        ]


panelHead : String -> String -> String -> Html msg
panelHead number title meta =
    div [ A.class "panel-head" ] [ span [ A.class "panel-number" ] [ text number ], h2 [] [ text title ], span [ A.class "meta" ] [ text meta ] ]


treeView : Model -> Node -> Int -> Node -> Html Msg
treeView model doc depth (Node n) =
    let
        closed =
            Set.member n.id model.collapsed

        leaf =
            n.stroke /= Nothing

        selected =
            n.id == model.selected

        live =
            model.cursor == List.length model.history && model.pending == Nothing

        droppable inside =
            [ E.stopPropagationOn "mouseup" (D.succeed ( Drop n.id inside, True )) ]
    in
    div []
        [ div
            ([ A.class
                ("tree-row"
                    ++ (if selected then
                            " selected"

                        else
                            ""
                       )
                    ++ (if n.hidden then
                            " is-hidden"

                        else
                            ""
                       )
                )
             , A.style "padding-left" (String.fromInt (10 + depth * 14) ++ "px")
             ]
                ++ (if live then
                        droppable False

                    else
                        []
                   )
            )
            [ if List.isEmpty n.children then
                span [ A.class "chevron empty" ] [ text "·" ]

              else
                button
                    [ A.class "chevron"
                    , E.onClick (Collapse n.id)
                    , A.attribute "aria-label"
                        ((if closed then
                            "Expand "

                          else
                            "Collapse "
                         )
                            ++ n.title
                        )
                    ]
                    [ text
                        (if closed then
                            "›"

                         else
                            "⌄"
                        )
                    ]
            , span
                [ A.class "grip"
                , A.draggable "false"
                , E.preventDefaultOn "mousedown"
                    (D.succeed
                        ( if live && n.id /= "scene" then
                            Drag n.id

                          else
                            DragEnd
                        , True
                        )
                    )
                , A.title "Drag this chunk"
                ]
                [ text "⠿" ]
            , button [ A.class "node-label", E.onClick (Select n.id), A.title n.prompt ]
                [ span
                    [ A.class
                        (if leaf then
                            "stroke-icon"

                         else
                            "folder-icon"
                        )
                    ]
                    [ text
                        (if leaf then
                            "╱"

                         else
                            "▱"
                        )
                    ]
                , text n.title
                ]
            , if leaf then
                text ""

              else
                span [ A.class "count" ] [ text (String.fromInt (strokeCount (Node n))) ]
            , if not leaf && live && model.dragged /= Nothing then
                span ([ A.class "drop-inside", A.title ("Move inside " ++ n.title) ] ++ droppable True) [ text "↳" ]

              else
                text ""
            ]
        , if closed then
            text ""

          else
            div [] (List.map (treeView model doc (depth + 1)) n.children)
        ]


canvas : Model -> Node -> Html Msg
canvas model doc =
    Svg.svg [ S.id "drawing", S.viewBox "0 0 620 640", S.attributeName "Paris postcard", A.attribute "role" "img", A.attribute "aria-label" "Interactive line drawing of the Eiffel Tower and the Seine" ]
        [ Svg.rect [ S.width "620", S.height "640", S.fill "#fcfaf5" ] []
        , Svg.circle [ S.cx "448", S.cy "172", S.r "46", S.fill "#efe7d2", S.opacity "0.52" ] []
        , Svg.path [ S.d "M42 490 Q200 477 310 483 T578 477 L578 602 L42 602 Z", S.fill "#e5eeeb", S.opacity "0.5" ] []
        , Svg.g [] (drawNode model.selected False False doc)
        ]


drawNode : String -> Bool -> Bool -> Node -> List (Svg Msg)
drawNode selected inherited hidden (Node n) =
    let
        active =
            inherited || n.id == selected

        invisible =
            hidden || n.hidden

        children =
            List.concatMap (drawNode selected active invisible) n.children
    in
    if invisible then
        []

    else
        case n.stroke of
            Nothing ->
                children

            Just s ->
                [ Svg.line
                    [ S.x1 (String.fromFloat s.x1)
                    , S.y1 (String.fromFloat s.y1)
                    , S.x2 (String.fromFloat s.x2)
                    , S.y2 (String.fromFloat s.y2)
                    , S.stroke
                        (if active && s.width < 8 then
                            "#cc754b"

                         else
                            s.color
                        )
                    , S.strokeWidth
                        (String.fromFloat
                            (if active then
                                s.width + 0.35

                             else
                                s.width
                            )
                        )
                    , S.strokeLinecap
                        (if s.width > 8 then
                            "butt"

                         else
                            "round"
                        )
                    , A.attribute "data-color" s.color
                    , A.attribute "data-width" (String.fromFloat s.width)
                    , E.onClick (Select n.id)
                    , S.class "drawn-stroke"
                    ]
                    [ Svg.title [] [ text n.prompt ] ]
                ]
                    ++ children


inspector : Model -> Node -> Bool -> Html Msg
inspector model doc live =
    case find model.selected doc of
        Nothing ->
            div [ A.class "inspector" ] [ p [] [ text "This intention has not been added yet. Continue the replay to see it." ] ]

        Just (Node n) ->
            div [ A.class "inspector" ]
                [ div [ A.class "inspector-heading" ] [ span [ A.class "eyebrow" ] [ text "SELECTED INTENTION" ], span [ A.class "selection-count" ] [ text (String.fromInt (strokeCount (Node n)) ++ " strokes") ] ]
                , h2 [] [ text n.title ]
                , p [ A.class "intent-copy" ] [ text n.prompt ]
                , div [ A.class "edit-tools" ]
                    [ div [ A.class "tool-group" ] [ span [ A.class "tool-label" ] [ text "MOVE" ], tool live "←" "Move left 12 units" (Nudge -12 0), tool live "↑" "Move up 12 units" (Nudge 0 -12), tool live "↓" "Move down 12 units" (Nudge 0 12), tool live "→" "Move right 12 units" (Nudge 12 0) ]
                    , div [ A.class "tool-group" ] [ span [ A.class "tool-label" ] [ text "ORDER" ], tool (live && n.id /= "scene") "↑" "Earlier in drawing order" (Reorder -1), tool (live && n.id /= "scene") "↓" "Later in drawing order" (Reorder 1) ]
                    , button [ E.onClick Redraw, A.disabled (not live), A.class "primary compact", A.title "Generate a new variation using this saved intention" ] [ text "↻ Redraw" ]
                    , button [ E.onClick Hide, A.disabled (not live), A.class "quiet compact" ]
                        [ text
                            (if n.hidden then
                                "Show chunk"

                             else
                                "Hide chunk"
                            )
                        ]
                    ]
                , Html.details [ A.class "edit-intent" ]
                    [ Html.summary [] [ text "Edit this intention" ]
                    , textarea [ A.value model.draft, E.onInput Edit, A.disabled (not live), A.attribute "aria-label" "Intention text", A.rows 4 ] []
                    , p [] [ text "AI will redraw this entire subtree. Other branches stay unchanged, and the old version remains in history." ]
                    , button [ A.class "primary", A.disabled (not live), E.onClick SaveIntent ]
                        [ text
                            (if model.pending == Nothing then
                                "Redraw subtree with AI"

                             else
                                "Redrawing…"
                            )
                        ]
                    ]
                , case model.generationError of
                    Just message ->
                        p [ A.class "generation-error", A.attribute "role" "alert" ] [ text message ]

                    Nothing ->
                        text ""
                , if model.pending /= Nothing then
                    p [ A.class "generation-progress", A.attribute "role" "status" ] [ text "Interpreting the intention and drawing its parts…" ]

                  else
                    text ""
                , if model.cursor == List.length model.history then
                    text ""

                  else
                    p [ A.class "past-note" ] [ text "Viewing an earlier state. Return to Latest to edit." ]
                ]


tool : Bool -> String -> String -> Msg -> Html Msg
tool enabled label title msg =
    button [ A.disabled (not enabled), A.title title, A.attribute "aria-label" title, E.onClick msg, A.class "icon-button" ] [ text label ]


historyView : Model -> Int -> Change -> Html Msg
historyView model index change =
    let
        expanded =
            Set.member index model.expandedHistory

        future =
            index >= model.cursor
    in
    div
        [ A.class
            ("history-entry"
                ++ (if future then
                        " future"

                    else
                        ""
                   )
                ++ (if index + 1 == model.cursor then
                        " current"

                    else
                        ""
                   )
            )
        ]
        [ div [ A.class "history-title-row" ]
            [ button [ A.class "history-dot", E.onClick (Seek (String.fromInt (index + 1))), A.title "View this moment" ] [ text (String.fromInt (index + 1)) ]
            , button
                [ A.class "history-title"
                , E.onClick (HistoryToggle index)
                , A.attribute "aria-expanded"
                    (if expanded then
                        "true"

                     else
                        "false"
                    )
                ]
                [ text change.title
                , span []
                    [ text
                        (if expanded then
                            "−"

                         else
                            "+"
                        )
                    ]
                ]
            ]
        , p [ A.class "history-why" ] [ text change.why ]
        , if expanded then
            div [ A.class "operations" ] (List.map (\op -> div [ A.class "operation" ] [ text (describe op) ]) change.operations ++ [ button [ A.class "text-button", E.onClick (Select change.intent) ] [ text "Select intention ↗" ] ])

          else
            text ""
        ]


describe : Operation -> String
describe op =
    case op of
        Add _ (Node n) ->
            "+ " ++ n.title ++ " · " ++ String.fromInt (strokeCount (Node n)) ++ " strokes"

        Move id parent index ->
            "↳ Move " ++ id ++ " into " ++ parent ++ " at " ++ String.fromInt (index + 1)

        Translate id dx dy ->
            "↔ " ++ id ++ " · Δ(" ++ String.fromFloat dx ++ ", " ++ String.fromFloat dy ++ ")"

        Visibility id hidden ->
            (if hidden then
                "Hide "

             else
                "Show "
            )
                ++ id

        Replace _ replacement ->
            "↻ Replace subtree · " ++ String.fromInt (strokeCount replacement) ++ " generated strokes"

        Revise _ prompt ->
            "✎ “" ++ prompt ++ "”"



-- Stable JSON log: replay never invokes a prompt interpreter.


encodeHistory : List Change -> J.Value
encodeHistory changes =
    J.object [ ( "version", J.int 1 ), ( "history", J.list encodeChange changes ) ]


encodeChange : Change -> J.Value
encodeChange c =
    J.object [ ( "title", J.string c.title ), ( "why", J.string c.why ), ( "intent", J.string c.intent ), ( "operations", J.list encodeOperation c.operations ) ]


encodeOperation : Operation -> J.Value
encodeOperation op =
    let
        obj kind fields =
            J.object (( "kind", J.string kind ) :: fields)
    in
    case op of
        Add parent child ->
            obj "add" [ ( "parent", J.string parent ), ( "node", encodeNode child ) ]

        Move id parent index ->
            obj "move" [ ( "id", J.string id ), ( "parent", J.string parent ), ( "index", J.int index ) ]

        Translate id dx dy ->
            obj "translate" [ ( "id", J.string id ), ( "dx", J.float dx ), ( "dy", J.float dy ) ]

        Visibility id hidden ->
            obj "visibility" [ ( "id", J.string id ), ( "hidden", J.bool hidden ) ]

        Replace id replacement ->
            obj "replace" [ ( "id", J.string id ), ( "node", encodeNode replacement ) ]

        Revise id prompt ->
            obj "revise" [ ( "id", J.string id ), ( "prompt", J.string prompt ) ]


encodeNode : Node -> J.Value
encodeNode (Node n) =
    J.object [ ( "id", J.string n.id ), ( "title", J.string n.title ), ( "prompt", J.string n.prompt ), ( "hidden", J.bool n.hidden ), ( "children", J.list encodeNode n.children ), ( "stroke", Maybe.map encodeStroke n.stroke |> Maybe.withDefault J.null ) ]


encodeStroke : Stroke -> J.Value
encodeStroke s =
    J.object [ ( "x1", J.float s.x1 ), ( "y1", J.float s.y1 ), ( "x2", J.float s.x2 ), ( "y2", J.float s.y2 ), ( "color", J.string s.color ), ( "width", J.float s.width ) ]


changeDecoder : D.Decoder Change
changeDecoder =
    D.map4 Change (D.field "title" D.string) (D.field "why" D.string) (D.field "intent" D.string) (D.field "operations" (D.list operationDecoder))


operationDecoder : D.Decoder Operation
operationDecoder =
    D.field "kind" D.string
        |> D.andThen
            (\kind ->
                case kind of
                    "add" ->
                        D.map2 Add (D.field "parent" D.string) (D.field "node" nodeDecoder)

                    "move" ->
                        D.map3 Move (D.field "id" D.string) (D.field "parent" D.string) (D.field "index" D.int)

                    "translate" ->
                        D.map3 Translate (D.field "id" D.string) (D.field "dx" D.float) (D.field "dy" D.float)

                    "visibility" ->
                        D.map2 Visibility (D.field "id" D.string) (D.field "hidden" D.bool)

                    "replace" ->
                        D.map2 Replace (D.field "id" D.string) (D.field "node" nodeDecoder)

                    "revise" ->
                        D.map2 Revise (D.field "id" D.string) (D.field "prompt" D.string)

                    _ ->
                        D.fail "Unknown operation"
            )


nodeDecoder : D.Decoder Node
nodeDecoder =
    D.map6 (\id title prompt hidden children stroke -> Node { id = id, title = title, prompt = prompt, hidden = hidden, children = children, stroke = stroke }) (D.field "id" D.string) (D.field "title" D.string) (D.field "prompt" D.string) (D.field "hidden" D.bool) (D.field "children" (D.list (D.lazy (\_ -> nodeDecoder)))) (D.field "stroke" (D.nullable strokeDecoder))


strokeDecoder : D.Decoder Stroke
strokeDecoder =
    D.map6 Stroke (D.field "x1" D.float) (D.field "y1" D.float) (D.field "x2" D.float) (D.field "y2" D.float) (D.field "color" D.string) (D.field "width" D.float)


generatedDecoder : D.Decoder Generated
generatedDecoder =
    D.map5 Generated (D.field "requestId" D.int) (D.field "revision" D.int) (D.field "node" nodeDecoder) (D.field "explanation" D.string) (D.field "model" D.string)
