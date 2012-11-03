xquery version "3.0";

(:~
 : A set of helper functions to access the application context from
 : within a module.
 :)
module namespace config="http://exist-db.org/xquery/apps/config";

declare namespace templates="http://exist-db.org/xquery/templates";
declare namespace repo="http://exist-db.org/xquery/repo";
declare namespace expath="http://expath.org/ns/pkg";

(: 
    Determine the application root collection from the current module load path.
:)
declare variable $config:app-root := 
    let $rawPath := system:get-module-load-path()
    let $modulePath :=
        (: strip the xmldb: part :)
        if (starts-with($rawPath, "xmldb:exist://")) then
            if (starts-with($rawPath, "xmldb:exist://embedded-eXist-server")) then
                substring($rawPath, 36)
            else
                substring($rawPath, 15)
        else
            $rawPath
    return
        substring-before($modulePath, "/modules")
;

declare variable $config:repo-descriptor := doc(concat($config:app-root, "/repo.xml"))/repo:meta;

declare variable $config:expath-descriptor := doc(concat($config:app-root, "/expath-pkg.xml"))/expath:package;

(:~
 : Resolve the given path using the current application context.
 : If the app resides in the file system,
 :)
declare function config:resolve($relPath as xs:string) {
    if (starts-with($config:app-root, "/db")) then
        doc(concat($config:app-root, "/", $relPath))
    else
        doc(concat("file://", $config:app-root, "/", $relPath))
};

(:~
 : Returns the repo.xml descriptor for the current application.
 :)
declare function config:repo-descriptor() as element(repo:meta) {
    $config:repo-descriptor
};

(:~
 : Returns the expath-pkg.xml descriptor for the current application.
 :)
declare function config:expath-descriptor() as element(expath:package) {
    $config:expath-descriptor
};

declare %templates:wrap function config:app-title($node as node(), $model as map(*)) as text() {
    $config:expath-descriptor/expath:title/text()
};

declare function config:app-meta($node as node(), $model as map(*)) as element()* {
    <meta xmlns="http://www.w3.org/1999/xhtml" name="description" content="{$config:repo-descriptor/repo:description/text()}"/>,
    for $author in $config:repo-descriptor/repo:author
    return
        <meta xmlns="http://www.w3.org/1999/xhtml" name="creator" content="{$author/text()}"/>
};

(:~
 : For debugging: generates a table showing all properties defined
 : in the application descriptors.
 :)
declare function config:app-info($node as node(), $model as map(*)) {
    let $expath := config:expath-descriptor()
    let $repo := config:repo-descriptor()
    return
        <table class="app-info">
            <tr>
                <td>app collection:</td>
                <td>{$config:app-root}</td>
            </tr>
            {
                for $attr in ($expath/@*, $expath/*, $repo/*)
                return
                    <tr>
                        <td>{node-name($attr)}:</td>
                        <td>{$attr/string()}</td>
                    </tr>
            }
            <tr>
                <td>Controller:</td>
                <td>{ request:get-attribute("$exist:controller") }</td>
            </tr>
        </table>
};

declare function config:expand-links($node as node(), $model as map(*), $base as xs:string?) {
    config:expand-links($node, $base)
};

declare %private function config:expand-links($node as node(), $base as xs:string?) {
    if ($node instance of element()) then
        let $href := $node/@href
        return
            if ($href) then
                let $expanded :=
                    if (starts-with($href, "/")) then
                        concat(request:get-context-path(), $href)
                    else
                        config:expand-link($href, $base)
                return
                    element { node-name($node) } {
                        attribute href { $expanded },
                        $node/@* except $href, $node/node()
                    }
            else
                element { node-name($node) } {
                    $node/@*, for $child in $node/node() return config:expand-links($child, $base)
                }
    else
        $node
};

declare %private function config:expand-link($href as xs:string, $base as xs:string?) {
    string-join(
        let $analyzed := analyze-string($href, "^\{([^\{\}]+)\}")
        for $component in $analyzed/*/*
        return
            typeswitch($component)
                case element(fn:match) return
                    let $arg := $component/fn:group/string()
                    let $name := if (contains($arg, "|")) then substring-before($arg, "|") else $arg
                    let $fallback := substring-after($arg, "|")
                    let $app := collection(concat("/db/", $name))
                    return
                        if ($app) then
                            concat(request:get-context-path(), request:get-attribute("$exist:prefix"), "/", $name, "/")
                        else if ($fallback) then
                            $base || $fallback
                        else
                            concat(request:get-context-path(), "/404.html")
                default return
                    $component/text()
        , ""
    )
};