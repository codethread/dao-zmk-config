#!/usr/bin/env nu

def "main check" [] {
  let msg = git log -n 1 --format="%s"
  let url = poll ($msg)
  log "Complete"
  ^open $url
}

def "main push" [...message: string] {
  if ($message | is-empty) { error make { msg: "Message empty", label: { text: "here", span: (metadata $message).span } } }
  let commit_msg = $"ct: ($message | str join ' ')"
  log "Commiting:" $commit_msg
  git add .
  git commit -m $commit_msg
  git push
  log "Polling"
  let url = poll $commit_msg
  log "Complete"
  ^open $url
}

def main [] { }

### helpers

def log [info: string, ...rest: string] {
  print $"(ansi green)($info)(ansi reset)"
  if ($rest | is-not-empty) {
    print $rest
  }
}

const query = `query BuildStatus {
  repository(owner: "codethread", name: "dao-zmk-config") {
    defaultBranchRef {
      name
      id
      target {
        ... on Commit {
          history(first: 1) {
            nodes {
              message
              checkSuites(first: 1) {
                nodes {
                  status
                  workflowRun {
                    url
                  }
                  # checkRuns(first: 1, filterBy: {checkName: "build / Merge Output Artifacts"}) {
                  #   nodes {
                  #     name
                  #     url
                  #     status
                  #   }
                  # }
                }
              }
            }
          }
        }
      }
    }
  }
}`

def poll [msg: string]: nothing -> string {
  let data = {
    query: $query
  }

  mut out = ""

  loop {
    let cmt = (http post --content-type application/json --headers [Authorization $"bearer ($env.GH_TOKEN)"] https://api.github.com/graphql $data
      | get data.repository.defaultBranchRef.target.history.nodes.0)

     log "Latest commit:" ($cmt | get message)

    if (($cmt | get message) != $msg) {
      log "Waiting"
      sleep 10sec
      continue
    }

    match ($cmt | get checkSuites.nodes) {
      [] => { print "Waiting for checks"; sleep 15sec; },
      [{ status: "COMPLETED", workflowRun: { url: $url } }] => { $out = $url; break },
      [$check] => { print ($check | table --expand); sleep 15sec; }
    }
  }

  $out
}
