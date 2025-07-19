#include "polkit.h"
#include <unistd.h>
#include <systemd/sd-login.h>
#include <stdio.h>
#include <polkitagent/polkitagent.h>
struct _MikaShellPolkitAuthenticationAgent
{
    PolkitAgentListener parent_instance;
};

G_DEFINE_TYPE(MikaShellPolkitAuthenticationAgent,
              mika_shell_polkit_authentication_agent,
              POLKIT_AGENT_TYPE_LISTENER)

static void
mika_shell_polkit_authentication_agent_initiate_authentication(
    PolkitAgentListener *listener,
    const gchar *action_id,
    const gchar *message,
    const gchar *icon_name,
    PolkitDetails *details,
    const gchar *cookie,
    GList *identities,
    GCancellable *cancellable,
    GAsyncReadyCallback callback,
    gpointer user_data)
{
    PolkitIdentity *identity = polkit_identity_from_string("unix-user:1000", NULL);
    PolkitAgentSession *session = polkit_agent_session_new(identity, cookie);
    gchar *password = "********";
    polkit_agent_session_initiate(session);
    polkit_agent_session_response(session, password);
}

static void
mika_shell_polkit_authentication_agent_class_init(MikaShellPolkitAuthenticationAgentClass *klass)
{
    PolkitAgentListenerClass *listener_class = POLKIT_AGENT_LISTENER_CLASS(klass);
    listener_class->initiate_authentication =
        mika_shell_polkit_authentication_agent_initiate_authentication;
}

static void
mika_shell_polkit_authentication_agent_init(MikaShellPolkitAuthenticationAgent *self)
{
}

// MikaShellPolkitAuthenticationAgent *
// mika_shell_polkit_authentication_agent_new(void)
// {
//     return g_object_new(MIKASHELL_TYPE_POLKIT_AUTHENTICATION_AGENT, NULL);
// }

// gchar *
// mika_shell_polkit_authentication_agent_register(MikaShellPolkitAuthenticationAgent *agent,
//                                                 GError **error_out)
// {
//     PolkitSubject *subject = polkit_unix_process_new(getpid());

//     if (!polkit_agent_listener_register(POLKIT_AGENT_LISTENER(agent),
//                                         POLKIT_AGENT_REGISTER_FLAGS_NONE,
//                                         subject,
//                                         "/org/mikashell/PolkitAuthenticationAgent",
//                                         NULL,
//                                         error_out))
//     {
//         return NULL;
//     }

//     return g_strdup("/org/mikashell/PolkitAuthenticationAgent");
// }

// void mika_shell_polkit_authentication_agent_unregister(MikaShellPolkitAuthenticationAgent *agent)
// {
//     polkit_agent_listener_unregister(POLKIT_AGENT_LISTENER(agent));
// }
