/* Company Compass — Terms & Conditions and Privacy Policy.
   One copy of the text, used by the app (Terms / Privacy links) and by the public legal page (legal.html).
   FILL IN BEFORE LAUNCH: OPERATOR_NAME (your full legal name). Then have the text checked by someone qualified. */
(function(){
  const OPERATOR_NAME = 'Jared [SURNAME]';
  const CONTACT_EMAIL = 'jazzamills516@gmail.com';
  const UPDATED = '16 October 2026';
  const mail = `<a href="mailto:${CONTACT_EMAIL}">${CONTACT_EMAIL}</a>`;

  const terms = `
  <p style="color:var(--muted);font-size:.78rem;">Last updated: ${UPDATED}</p>
  <h3>1. Who we are and accepting these Terms</h3>
  <p>Company Compass ("the App") is operated by ${OPERATOR_NAME}, an individual based in Gauteng, South Africa ("we", "us"). You can reach us at ${mail}. By creating an account or using the App you agree to these Terms on behalf of yourself and the company you use it for. If you don't agree, please don't use the App.</p>
  <h3>2. What the App is</h3>
  <p>Company Compass is online accounting, invoicing, payroll and compliance software for South African businesses. It helps you capture and report on revenue, expenses, assets, liabilities, invoices, bills, bank transactions, payroll and related returns.</p>
  <h3>3. Free beta</h3>
  <p>The App is currently in a free beta. Features may change, be added or be removed while we improve it. If we introduce charges, we will tell account owners by email at least 30 days beforehand, and you will not be charged unless you choose a paid plan.</p>
  <h3>4. Not financial, tax or legal advice</h3>
  <p>Figures and documents the App produces — including VAT201 figures, PAYE, UIF and SDL calculations, payslips, IRP5/IT3(a) certificates, EMP201 and EMP501 figures, e@syFile exports, provisional tax estimates, depreciation and financial statements — are tools to help you, not professional advice. Check them, or have a registered accountant or tax practitioner check them, before you submit anything to SARS or rely on it for official purposes. You remain responsible for your company's returns and payments.</p>
  <h3>5. Accounts, roles and security</h3>
  <p>Anyone may sign up to set up their own company. The account owner and management users decide who else gets access and what they can see. Keep your login details confidential; you are responsible for activity carried out under your account. Tell us straight away at ${mail} if you think your account has been misused.</p>
  <h3>6. Your data</h3>
  <p>You and your company own the records and documents you put into the App, and you can export them at any time. You are responsible for their accuracy and for having a lawful reason to capture personal information about other people (such as your clients, suppliers and employees). For that information your company is the "responsible party" under the Protection of Personal Information Act (POPIA) and we process it only on your behalf, as described in our Privacy Policy.</p>
  <h3>7. Keep your own copies</h3>
  <p>We take reasonable care to keep the App available and your data safe, but during the beta please export your records regularly (Settings → Data Export) and keep the documents the law requires you to keep. The App is provided "as is" and "as available".</p>
  <h3>8. Other services</h3>
  <p>Some features rely on other providers: card payments through Yoco (an agreement between you and Yoco), email delivery through Resend, and bill scanning through Anthropic. We can't guarantee that every email is delivered or that every scanned document is read correctly — always check scanned bills before saving them.</p>
  <h3>9. Acceptable use</h3>
  <p>Don't use the App for anything unlawful, to store information you're not allowed to hold, to send spam, or to try to get around permissions, approvals or security. We may suspend accounts that do.</p>
  <h3>10. Limitation of liability</h3>
  <p>To the extent the law allows, we are not liable for indirect or consequential loss, for penalties or interest charged because of a return or payment, or for decisions made on the strength of the App's reports, and our total liability is limited to the fees you paid us in the 12 months before the claim (nothing during the free beta). Nothing in these Terms limits rights you have that cannot be excluded by law.</p>
  <h3>11. Closing your account</h3>
  <p>You can stop using the App and ask us to close your company's account at any time by emailing ${mail}. Export your records first; after closure we delete them as set out in the Privacy Policy.</p>
  <h3>12. Law and changes</h3>
  <p>These Terms are governed by the law of South Africa. We may update them; we'll show the date of the latest version here and tell account owners about important changes. Using the App after a change means you accept the updated Terms.</p>
`;

  const privacy = `
  <p style="color:var(--muted);font-size:.78rem;">Last updated: ${UPDATED}</p>
  <h3>1. Who we are</h3>
  <p>Company Compass is operated by ${OPERATOR_NAME} ("we", "us"), an individual based in Gauteng, South Africa. This policy explains how we handle personal information under the Protection of Personal Information Act, 2013 (POPIA). Our Information Officer is ${OPERATOR_NAME}, contactable at ${mail}.</p>
  <h3>2. Two kinds of information</h3>
  <p><strong>Your account information</strong> — your name, email address, role and login activity. For this we are the responsible party.</p>
  <p><strong>Your company's records</strong> — the clients, suppliers, employees, invoices, payroll, bank transactions and documents your company captures. These often include other people's personal information, such as names, contact details, ID numbers, tax numbers, bank details and salaries. For these records your company is the responsible party and we act as its operator: we process them only to provide the App to you, keep them secure and confidential, and do not use them for anything else.</p>
  <h3>3. How we use information</h3>
  <p>To run the App and its features (including emailing invoices, statements and reminders when you ask the App to), to keep it secure, to answer your questions, to tell you about important changes, and to meet legal obligations. We do not sell personal information, use it for advertising, or share it except as described below.</p>
  <h3>4. Service providers and where information is stored</h3>
  <p>We use these providers, each bound by data-protection obligations, to run the App:</p>
  <ul>
    <li><strong>Supabase</strong> — database, file storage, logins and server functions. Data is stored in Ireland (European Union).</li>
    <li><strong>Vercel</strong> — hosts the website and app pages.</li>
    <li><strong>Resend</strong> — sends the emails you ask the App to send (United States).</li>
    <li><strong>Anthropic</strong> — reads a bill or slip only when you use "Scan a bill" (United States). Anthropic's commercial terms say it does not use this data to train its models.</li>
    <li><strong>Yoco</strong> — handles card payments when you use Pay-now links (South Africa). Card details go straight to Yoco; we never see them.</li>
    <li><strong>jsDelivr and cdnjs</strong> — deliver some of the App's program code to your browser, so they see your IP address. <strong>Frankfurter</strong> supplies exchange rates; no personal information is sent to it.</li>
  </ul>
  <p>Because some of these providers are outside South Africa, personal information is transferred across borders. We only use providers that are subject to data-protection law or agreements giving a level of protection comparable to POPIA, as section 72 of POPIA requires.</p>
  <h3>5. Security</h3>
  <p>Information travels over encrypted connections. Each company's records are separated by database security rules, access inside a company follows the roles and permissions its management sets, changes are recorded in an activity log, and uploaded documents are private and opened only through short-lived links. If we become aware of a security compromise affecting personal information, we will notify the Information Regulator and the affected parties as POPIA requires.</p>
  <h3>6. How long we keep information</h3>
  <p>We keep your company's records while its account is open so that its history and reports stay complete. If an account is closed, we delete its records within 90 days, unless the law requires us to keep something longer. Remember that your company may have its own legal duty to keep accounting and payroll records for several years, so export them before closing.</p>
  <h3>7. Your rights</h3>
  <p>You may ask to see the personal information we hold about you, ask us to correct or delete it, or object to how it is used, by emailing ${mail}. If your information was captured by a company that uses the App (for example your employer), please contact that company first — we will help them respond. You also have the right to complain to the Information Regulator (<a href="https://inforegulator.org.za" target="_blank" rel="noopener">inforegulator.org.za</a>).</p>
  <h3>8. Browser storage</h3>
  <p>The App uses your browser's storage to keep you signed in and to remember preferences such as light or dark mode. It does not use advertising or tracking cookies.</p>
  <h3>9. Children</h3>
  <p>The App is for businesses and is not intended for people under 18.</p>
  <h3>10. Changes</h3>
  <p>We will update this policy as the App changes and show the date of the latest version at the top. Questions? Email ${mail}.</p>
`;

  window.CC_LEGAL = { operator: OPERATOR_NAME, email: CONTACT_EMAIL, updated: UPDATED, terms, privacy };
})();
