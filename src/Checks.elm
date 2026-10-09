port module Checks exposing (main)

import Json.Decode as D
import Json.Encode as J
import Main as M exposing (Node(..), Operation(..))
import Platform


port report : J.Value -> Cmd msg


main : Program () () Never
main =
    Platform.worker { init = \_ -> ( (), report checks ), update = \_ model -> ( model, Cmd.none ), subscriptions = \_ -> Sub.none }


checks : J.Value
checks =
    let
        doc =
            List.foldl M.applyChange M.root M.seedHistory

        moved =
            M.apply (Move "tower" "river" 0) doc

        cycled =
            M.apply (Move "tower" "braces-left" 0) doc

        translated =
            M.apply (Translate "tower" 12 -5) doc

        position tree =
            M.find "leg-left-0" tree |> Maybe.andThen (\(Node n) -> n.stroke) |> Maybe.map (\s -> ( s.x1, s.y1 ))

        decoded =
            D.decodeValue (D.field "history" (D.list M.changeDecoder)) (M.encodeHistory M.seedHistory) |> Result.map (List.foldl M.applyChange M.root)

        renamed =
            M.apply (Revise "tower" "A new intention") doc

        title tree =
            M.find "tower" tree |> Maybe.map (\(Node n) -> n.prompt)

        tests =
            [ ( "Seed contains 140 strokes", M.strokeCount doc == 140 )
            , ( "Reparent preserves all strokes", M.strokeCount moved == 140 )
            , ( "Reparent removes old location"
              , case doc of
                    Node _ ->
                        case moved of
                            Node n ->
                                not (List.any (\(Node child) -> child.id == "tower") n.children)
              )
            , ( "Reparent preserves exact subtree", M.find "tower" doc == (M.find "river" moved |> Maybe.andThen (M.find "tower")) )
            , ( "Reject descendant cycle", cycled == doc )
            , ( "Reject root move", M.apply (Move "scene" "river" 0) doc == doc )
            , ( "Reject missing destination without data loss", M.apply (Move "tower" "missing" 0) doc == doc )
            , ( "Translate entire chunk", position translated == Just ( 306, 230 ) )
            , ( "Translate leaves other chunks untouched", M.find "river" translated == M.find "river" doc )
            , ( "JSON round-trip replays identically", decoded == Ok doc )
            , ( "Prefix replay excludes future boat", M.find "boat" (List.foldl M.applyChange M.root (List.take 5 M.seedHistory)) == Nothing )
            , ( "Intent revision preserves old document", title renamed == Just "A new intention" && title doc /= title renamed )
            , ( "Visibility preserves geometry", M.strokeCount (M.apply (Visibility "tower" True) doc) == 140 )
            ]
    in
    J.list (\( name, passed ) -> J.object [ ( "name", J.string name ), ( "passed", J.bool passed ) ]) tests
