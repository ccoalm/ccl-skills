// Jenkins declarative pipeline — run tests, publish Feishu report, comment on PR.
//
// Replace <unit> placeholders with your deployable-unit directory.
//
// Required Jenkins credentials (Manage Jenkins → Credentials):
//   lark-bot-app-id        (Secret Text)
//   lark-bot-app-secret    (Secret Text)
//   github-token           (Secret Text, repo:status + pull_requests:write)
//
// Committed in <unit>/test/.report-config.json: base_token, table_id, report_doc_url
//
// Requires plugins: github-pullrequest (or similar for PR detection),
// Pipeline: Stage View, Credentials Binding.

pipeline {
  agent any

  environment {
    UNIT = '<unit>'
    LAST_RUN_FILE = "${WORKSPACE}/${UNIT}/test/results/last-run.json"
  }

  stages {
    stage('Setup') {
      steps {
        dir("${UNIT}") {
          // Install lark-cli
          withCredentials([
            string(credentialsId: 'lark-bot-app-id', variable: 'LARK_BOT_APP_ID'),
            string(credentialsId: 'lark-bot-app-secret', variable: 'LARK_BOT_APP_SECRET'),
          ]) {
            sh '''
              npm i -g @larksuiteoapi/lark-cli
              # Pipe secret via stdin so it never appears in ps/argv.
              printf '%s' "$LARK_BOT_APP_SECRET" | \
                lark-cli config init \
                  --app-id "$LARK_BOT_APP_ID" \
                  --app-secret-stdin \
                  --brand feishu
            '''
          }
        }
      }
    }

    stage('Restore last-run snapshot') {
      steps {
        // Use Jenkins Artifact Manager or external storage to persist last-run.json
        // across builds. Simplest: copyArtifacts from the last successful build.
        script {
          try {
            copyArtifacts(
              projectName: env.JOB_NAME,
              filter: "${UNIT}/test/results/last-run.json",
              selector: lastSuccessful(),
              optional: true
            )
          } catch (Exception e) {
            echo "No prior snapshot — first run for this branch."
          }
        }
      }
    }

    stage('Test + Report') {
      steps {
        dir("${UNIT}") {
          // TC_SIDECAR_STRICT=1 makes sidecar write failures fail tests
          // (no silent Bitable staleness when CI passes).
          sh '''
            export TC_SIDECAR_STRICT=1
            npm ci
            make report-run
          '''
        }
      }
    }
    // Note: PR comment is moved to post{always{}} below — it MUST land even
    // on red builds, which is when the regression summary is most useful.
  }

  post {
    // Runs on every build (success or failure). PR comment FIRST — that's
    // the most useful signal for devs when the build is red.
    always {
      script {
        if (env.CHANGE_ID) {
          dir("${UNIT}") {
            withCredentials([string(credentialsId: 'github-token', variable: 'GH_TOKEN')]) {
              sh '''
                python test/scripts/gen_report.py \
                  --config test/.report-config.json --pr-summary --fail-on=never > /tmp/pr-summary.md || true
                if [ -s /tmp/pr-summary.md ]; then
                  gh pr comment "${CHANGE_ID}" --body-file /tmp/pr-summary.md \
                    --repo "${CHANGE_URL%/pull/*}" || true
                fi
              '''
            }
          }
        }
      }
      archiveArtifacts artifacts: "${UNIT}/test/results/**", allowEmptyArchive: true
      junit testResults: "${UNIT}/test/results/*.xml", allowEmptyResults: true
    }
  }
}
