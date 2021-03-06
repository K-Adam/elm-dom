module DOM
    exposing
        ( Rectangle
        , boundingClientRect
        , childNode
        , childNodes
        , tagName
        , className
        , classList
        , currentTarget
        , nextSibling
        , offsetHeight
        , offsetLeft
        , offsetParent
        , offsetTop
        , offsetWidth
        , parentElement
        , findAncestor
        , previousSibling
        , scrollLeft
        , scrollTop
        , target
        , hasClass
        , isTag
        , and
        , or
        , negate
        , textContent
        )

{-| You read values off the DOM by constructing a JSON decoder.
See the `target` value for example use.


# Traversing the DOM

@docs target, currentTarget, offsetParent, parentElement, findAncestor, nextSibling, previousSibling, childNode, childNodes


# Geometry

Decoders for reading sizing etc. properties off the DOM. All decoders return
measurements in pixels.

Refer to, e.g.,
[the Mozilla documentation](https://developer.mozilla.org/en-US/docs/Web/API/CSS_Object_Model/Determining_the_dimensions_of_elements)
for the precise semantics of these measurements. See also
[this stackoverflow answer](https://stackoverflow.com/questions/294250/how-do-i-retrieve-an-html-elements-actual-width-and-height).

@docs offsetWidth, offsetHeight
@docs offsetLeft, offsetTop
@docs Rectangle, boundingClientRect


# Scroll

@docs scrollLeft, scrollTop

# Predicates

@docs hasClass, isTag
@docs and, or, negate

# Miscellanous

@docs tagName
@docs className, classList
@docs textContent

-}

import Json.Decode as Decode exposing (Decoder, andThen, at, field)
import Dict

-- TRAVERSING

{-| Get the target DOM element of an event. You will usually start with this
decoder. E.g., to make a button which when clicked emit an Action that carries
the width of the button:

    import DOM exposing (offsetWidth, target)

    myButton : Html Float
    myButton =
        button
            [ on "click" (target offsetWidth) ]
            [ text "Click me!" ]

-}
target : Decoder a -> Decoder a
target decoder =
    field "target" decoder


{-| Get the currentTarget DOM element of an event.
-}
currentTarget : Decoder a -> Decoder a
currentTarget decoder =
    field "currentTarget" decoder


{-| Get the offsetParent of the current element. Returns first argument if the current
element is already the root; applies the second argument to the parent element
if not.

To do traversals of the DOM, exploit that Elm allows recursive values.

-}
offsetParent : a -> Decoder a -> Decoder a
offsetParent x decoder =
    Decode.oneOf
        [ field "offsetParent" <| Decode.null x
        , field "offsetParent" decoder
        ]


{-| Get the next sibling of an element.
-}
nextSibling : Decoder a -> Decoder a
nextSibling decoder =
    field "nextSibling" decoder


{-| Get the previous sibling of an element.
-}
previousSibling : Decoder a -> Decoder a
previousSibling decoder =
    field "previousSibling" decoder


{-| Get the parent of an element.
-}
parentElement : Decoder a -> Decoder a
parentElement decoder =
    field "parentElement" decoder

{-| Get the closest ancestor of an element that satisfies the provided predicate.
-}
findAncestor : Decoder Bool -> Decoder a -> Decoder (Maybe a)
findAncestor predicate decoder = findElement predicate decoder |> parentElement

findElement : Decoder Bool -> Decoder a -> Decoder (Maybe a)
findElement predicate decoder = Decode.oneOf
  [ Decode.null Nothing
  , Decode.andThen (\b ->
        if b then
          Decode.map Just decoder
        else
          findAncestor predicate decoder
      )
      predicate
  ]

{-| Find the ith child of an element.
-}
childNode : Int -> Decoder a -> Decoder a
childNode idx =
    at [ "childNodes", String.fromInt idx ]


{-| Get the children of an element.
-}
childNodes : Decoder a -> Decoder (List a)
childNodes decoder =
    let
        loop idx xs =
            Decode.maybe (field (String.fromInt idx) decoder)
                |> andThen
                    (Maybe.map (\x -> loop (idx + 1) (x :: xs))
                        >> Maybe.withDefault (Decode.succeed xs)
                    )
    in
    (field "childNodes" <| loop 0 [])
        |> Decode.map List.reverse



-- GEOMETRY


{-| Get the width of an element in pixels; underlying implementation
reads `.offsetWidth`.
-}
offsetWidth : Decoder Float
offsetWidth =
    field "offsetWidth" Decode.float


{-| Get the heigh of an element in pixels. Underlying implementation
reads `.offsetHeight`.
-}
offsetHeight : Decoder Float
offsetHeight =
    field "offsetHeight" Decode.float


{-| Get the left-offset of the element in the parent element in pixels.
Underlying implementation reads `.offsetLeft`.
-}
offsetLeft : Decoder Float
offsetLeft =
    field "offsetLeft" Decode.float


{-| Get the top-offset of the element in the parent element in pixels.
Underlying implementation reads `.offsetTop`.
-}
offsetTop : Decoder Float
offsetTop =
    field "offsetTop" Decode.float


-- SCROLL

{-| Get the amount of left scroll of the element in pixels.
Underlying implementation reads `.scrollLeft`.
-}
scrollLeft : Decoder Float
scrollLeft =
    field "scrollLeft" Decode.float


{-| Get the amount of top scroll of the element in pixels.
Underlying implementation reads `.scrollTop`.
-}
scrollTop : Decoder Float
scrollTop =
    field "scrollTop" Decode.float


{-| Types for rectangles.
-}
type alias Rectangle =
    { top : Float
    , left : Float
    , width : Float
    , height : Float
    }


{-| Obsolete: since Elm 0.19 use Browser.Dom.getElement.

 Approximation of the method
[getBoundingClientRect](https://developer.mozilla.org/en-US/docs/Mozilla/Tech/XPCOM/Reference/Floaterface/nsIDOMClientRect),
based off
[this stackoverflow answer](https://stackoverflow.com/questions/442404/retrieve-the-position-x-y-of-an-html-element).

NB! This decoder produces wrong results if a parent element is scrolled and
does not have explicit positioning (e.g., `position: relative;`); see
[this issue](https://github.com/debois/elm-dom/issues/4).

Also note that this decoder is likely computationally expensive and may produce
results that differ slightly from `getBoundingClientRect` in browser-dependent
ways.
-}
boundingClientRect : Decoder Rectangle
boundingClientRect =
    Decode.map3
        (\( x, y ) width height ->
            { top = y
            , left = x
            , width = width
            , height = height
            }
        )
        (position 0 0)
        offsetWidth
        offsetHeight



{- This is what we're implementing (from the above link).

   function getOffset( el ) {
     var _x = 0;
     var _y = 0;
     while( el && !isNaN( el.offsetLeft ) && !isNaN( el.offsetTop ) ) {
       _x += el.offsetLeft - el.scrollLeft;
       _y += el.offsetTop - el.scrollTop;
       el = el.offsetParent;
     }
     return { top: _y, left: _x };
   }
   var x = getOffset( document.getElementById('yourElId') ).left; )
-}


position : Float -> Float -> Decoder ( Float, Float )
position x y =
    Decode.map4
        (\scrollLeftP scrollTopP offsetLeftP offsetTopP ->
            ( x + offsetLeftP - scrollLeftP, y + offsetTopP - scrollTopP )
        )
        scrollLeft
        scrollTop
        offsetLeft
        offsetTop
        |> andThen
            (\( x_, y_ ) ->
                offsetParent ( x_, y_ ) (position x_ y_)
            )



-- PREDICATES

{-| Checks if an element has a given class.
-}
hasClass : String -> Decoder Bool
hasClass cName = classList |> Decode.map (List.member cName)

{-| Compares the tag name of an element to the parameter. The tName parameter has to be uppercased
-}
isTag : String -> Decoder Bool
isTag tName = tagName |> Decode.map ( (==) tName )

{-| Joins two predicates with an and operator
-}
and : Decoder Bool -> Decoder Bool -> Decoder Bool
and = Decode.map2 (&&)

{-| Joins two predicates with an or operator
-}
or : Decoder Bool -> Decoder Bool -> Decoder Bool
or = Decode.map2 (||)

{-| Inverses a predicate
-}
negate : Decoder Bool -> Decoder Bool
negate = Decode.map not

-- MISC

{-| Get the tag name of an element.
-}
tagName : Decoder String
tagName =
    at [ "tagName" ] Decode.string

{-| Get the class name(s) of an element.
-}
className : Decoder String
className =
    at [ "className" ] Decode.string

{-| Get the class list of an element.
    typeof classList is object, so we can not call Decode.list
-}
classList : Decoder (List String)
classList =
    at [ "classList" ]
      ( Decode.dict Decode.string |> Decode.map Dict.values )

{-| Get the text content of an element.
-}
textContent : Decoder String
textContent = at [ "textContent" ] Decode.string
