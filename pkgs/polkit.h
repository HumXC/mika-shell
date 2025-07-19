#pragma once

#define POLKIT_AGENT_I_KNOW_API_IS_SUBJECT_TO_CHANGE
#include <polkitagent/polkitagent.h>
#include <glib-object.h>

G_BEGIN_DECLS

#define MIKASHELL_TYPE_POLKIT_AUTHENTICATION_AGENT \
    (mika_shell_polkit_authentication_agent_get_type())

G_DECLARE_FINAL_TYPE(MikaShellPolkitAuthenticationAgent,
                     mika_shell_polkit_authentication_agent,
                     MIKASHELL,
                     POLKIT_AUTHENTICATION_AGENT,
                     PolkitAgentListener)

MikaShellPolkitAuthenticationAgent *mika_shell_polkit_authentication_agent_new(void);

gchar *mika_shell_polkit_authentication_agent_register(MikaShellPolkitAuthenticationAgent *agent,
                                                       GError **error_out);

void mika_shell_polkit_authentication_agent_unregister(MikaShellPolkitAuthenticationAgent *agent);

G_END_DECLS
