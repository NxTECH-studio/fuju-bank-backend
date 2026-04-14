Release {{ .Year }}-{{ .Month }}-{{ .Date }}
# Pull Requests

| PR | Title | Author |
|---|-------|--------|
{{ range $i, $pull := .Pulls }}| #{{ $pull.Number }} | {{ $pull.Title }} | {{ $pull.User.Login }} |
{{ end }}
